package com.newgonzo.cdg
{
	import flash.display.BitmapData;
	import flash.geom.Point;
	import flash.utils.ByteArray;
	import flash.utils.getTimer;
	
	public class CDGFile
	{
		// CDG Command Code
		public static const CDG_COMMAND:int = 0x09;
		
		// This is the size of the display as defined by the CDG specification.
		// The pixels in this region can be painted, and scrolling operations
		// rotate through this number of pixels.
		public static const CDG_FULL_WIDTH:int = 300;
		public static const CDG_FULL_HEIGHT:int = 216;
		
				
		// This is the size of the screen that is actually intended to be
		// visible.  It is the center area of CDG_FULL.  
		public static const CDG_DISPLAY_WIDTH:int = 294;
		public static const CDG_DISPLAY_HEIGHT:int = 204;
		
		public static const COLOUR_TABLE_SIZE:int = 16;
		
				
		// Bitmask for all CDG fields
		public static const CDG_MASK:int = 0x3F;
		public static const CDG_COLOR_MASK:int = 0x0F;
		public static const CDG_ROW_MASK:int = 0x1F;
		public static const CDG_COLUMN_MASK:int = 0x3F;
		public static const CDG_DOUBLE_MASK:int = 0x3F3F;
		
		public static const CDG_PACKET_SIZE:int = 24;
		public static const TILE_HEIGHT:int = 12;
		public static const TILE_WIDTH:int = 6;
		
				// CDG Instruction Codes
		public static const CDG_INST_MEMORY_PRESET:int = 1;
		public static const CDG_INST_BORDER_PRESET:int = 2;
		public static const CDG_INST_TILE_BLOCK:int = 6;
		public static const CDG_INST_SCROLL_PRESET:int = 20;
		public static const CDG_INST_SCROLL_COPY:int = 24;
		public static const CDG_INST_DEF_TRANSP_COL:int = 28;
		public static const CDG_INST_LOAD_COL_TBL_LO:int = 30;
		public static const CDG_INST_LOAD_COL_TBL_HIGH:int = 31;
		public static const CDG_INST_TILE_BLOCK_XOR:int = 38;
		
		private var cdgBytes:ByteArray;
		private var cdgDuration:int;
		
		private var cdgPositionMs:int;
		
		private var output:BitmapData;
		private var buffer:BitmapData;
		private var indices:Array;
		
		private var colorTable:Array;
		
		private var presetColorIndex:int;
		private var borderColorIndex:int;
		private var transparentColor:int;
		
		private var hOffset:int = 0;
		private var vOffset:int = 0;
		
		public function CDGFile(bytes:ByteArray)
		{
			cdgBytes = bytes;
			
			// duration of one packet is 1/300 seconds (4 packets per sector, 75 sectors per second)
			cdgDuration = ((cdgBytes.length / CDG_PACKET_SIZE) * 1000) / 300;
			
			colorTable = new Array();
			for (var i:int = 0; i<16; i++) colorTable[i] == 0;
			
			// init surface
			output = new BitmapData(CDG_FULL_WIDTH, CDG_FULL_HEIGHT, false, 0x000000);
			buffer = new BitmapData(CDG_FULL_WIDTH, CDG_FULL_HEIGHT, false, 0x000000);
			// used as a 2d array
			indices = buildIndicesArray();
			//indices = new BitmapData(CDG_FULL_WIDTH, CDG_FULL_HEIGHT, false, 0x000000);
		}
		
		public function get image():BitmapData
		{
			return output;
		}
		
		public function reset():void
		{
			cdgDuration = 0;
			cdgPositionMs = 0;
		}


		public function renderPosition(ms:int):void
		{
			var packet:CDGPacket;
			var numPacks:int = 0;
			
			if(ms < cdgPositionMs)
			{
				cdgBytes.position = 0;
				cdgPositionMs = 0;
			}
			
			numPacks = ms - cdgPositionMs;
			numPacks /= 10;
			
			cdgPositionMs += numPacks * 10;
			numPacks *= 3;
			
			packet = readPacket();
			
			trace("cdgPositionMs: " + cdgPositionMs);
			trace("ms: " + ms);
			trace("numPacks: " + numPacks);
			
			while(numPacks-- > 0 && packet)
			{
				processPacket(packet);
				packet = readPacket();
			}
			
			//render();
		}
		
		public function readPacket():CDGPacket
		{
			var packet:CDGPacket = new CDGPacket();
			
			packet.command = cdgBytes.readByte();
			packet.instruction = cdgBytes.readByte();
			
			cdgBytes.readBytes(packet.parityQ, 0, 2);
			cdgBytes.readBytes(packet.data, 0, 16);
			cdgBytes.readBytes(packet.parityP, 0, 4);
			
			return packet;
		}
		
		public function processPacket(packet:CDGPacket):void
		{
			var instruction:int;
			
			if((packet.command & CDG_MASK) == CDG_COMMAND) 
			{
				instruction = (packet.instruction & CDG_MASK);
				
				switch (instruction) 
				{
					case CDG_INST_MEMORY_PRESET:
						memoryPreset(packet);
						break;
					
					case CDG_INST_BORDER_PRESET:
						borderPreset(packet);
						break;
					
					case CDG_INST_TILE_BLOCK:
						tileBlock(packet, false);
						break;
					
					case CDG_INST_SCROLL_PRESET:
						scroll(packet, false);
						break;
					
					case CDG_INST_SCROLL_COPY:
						scroll(packet, true);
						break;
					
					case CDG_INST_DEF_TRANSP_COL:
						defineTransparentColor(packet);
						break;
					
					case CDG_INST_LOAD_COL_TBL_LO:
						loadColorTable(packet, 0);
						break;
					
					case CDG_INST_LOAD_COL_TBL_HIGH:
						loadColorTable(packet, 1);
						break;
					
					case CDG_INST_TILE_BLOCK_XOR:
						tileBlock(packet, true);
						break;
					
					default:
						// Ignore the unsupported commands
						trace("WHAT IS THIS?");
						break;
				}
				
				render();
			}
		}
		
		protected function buildIndicesArray():Array
		{
			var a:Array = new Array();
			var b:Array;
			var i:int = 0;
			var j:int = 0;
			
			for(i = 0; i < CDG_FULL_WIDTH; i++)
			{
				b = new Array();
				a[i] = b;
				
				for(j = 0; j < CDG_FULL_HEIGHT; j++)
				{
					b[j] = 0;
				}
			}
			
			return a;
		}
		
		protected function memoryPreset(packet:CDGPacket):void
		{
			//trace("memoryPreset(" + packet + ")");
			
			var color:int;
			var ri:int;
			var ci:int;
			var repeat:int;
			
			color = packet.data[0] & CDG_COLOR_MASK;
			repeat = packet.data[1] & 0x0F;
			
			////trace("mem preset color: " + color);
			
			// Our new interpretation of CD+G Revealed is that memory preset
			// commands should also change the border
			presetColorIndex = color;
			borderColorIndex = presetColorIndex;
			
			//trace("presetColorIndex: " + presetColorIndex);
			
			// we have a reliable data stream, so the repeat command 
			// is executed only the first time
			if (repeat == 0)
			{
				// Note that this may be done before any load colour table
				// commands by some CDGs. So the load colour table itself
				// actual recalculates the RGB values for all pixels when
				// the colour table changes.
				
				// Set the preset colour for every pixel. Must be stored in 
				// the pixel colour table indeces array
				for (ri = 0; ri < CDG_FULL_HEIGHT; ++ri) 
				{
					for (ci = 0; ci < CDG_FULL_WIDTH; ++ci) 
					{
						indices[ci][ri] = presetColorIndex;
						buffer.setPixel(ci, ri, colorTable[presetColorIndex]);
					}
				}
			}
		}
		
		protected function borderPreset(packet:CDGPacket):void
		{
			//trace("borderPreset(" + packet + ")");
			
			var color:int, ri:int, ci:int;
			
			color = packet.data[0] & CDG_COLOR_MASK;
			borderColorIndex = color;
			
			// The border area is the area contained with a rectangle 
			// defined by (0,0,300,216) minus the interior pixels which are contained
			// within a rectangle defined by (6,12,294,204).
			
			////trace("border preset index: "+ borderColorIndex);
			////trace("border preset color: " + color);
			
			for (ri = 0; ri < CDG_FULL_HEIGHT; ++ri) 
			{
				for (ci = 0; ci < 6; ++ci)
				{
					buffer.setPixel(ci, ri, colorTable[color]);
					indices[ci][ri] = color;
				}
			
				for (ci = CDG_FULL_WIDTH - 6; ci < CDG_FULL_WIDTH; ++ci)
				{
					buffer.setPixel(ci, ri, colorTable[color]);
					indices[ci][ri] =  color;
				}
			}
			
			for (ci = 6; ci < CDG_FULL_WIDTH - 6; ++ci) 
			{
				for (ri = 0; ri < 12; ++ri)
				{
					buffer.setPixel(ci, ri, colorTable[color]);
					indices[ci][ri] =  color;
				}
			
				for (ri = CDG_FULL_HEIGHT - 12; ri < CDG_FULL_HEIGHT; ++ri)
				{
					buffer.setPixel(ci, ri, colorTable[color]);
					indices[ci][ri] =  color;
				}
			}
		}
		
		protected function loadColorTable(packet:CDGPacket, table:int):void
		{
			//trace("loadColorTable(" + packet + ", " + table + ")");
			
			var red:uint, green:uint, blue:uint, color:uint;
			var rgb:int;
			var i:int;
			
			for (i = 0; i < 8; i++) 
			{
				// [---high byte---]   [---low byte----]
				// 7 6 5 4 3 2 1 0     7 6 5 4 3 2 1 0
				// X X r r r r g g     X X g g b b b b
				
				color = (packet.data[2 * i] & CDG_MASK) << 8;
				color = color + (packet.data[(2 * i) + 1] & CDG_MASK);
				color = ((color & 0x3F00) >> 2) | (color & 0x003F);
				
				
				red = ((color & 0x0F00) >> 8) * 17; 
				green = ((color & 0x00F0) >> 4) * 17;
				blue = ((color & 0x000F)) * 17;
				
				////trace("red: " + red + " green: " + green + " blue: " + blue);
			
				rgb = red << 16 | green << 8 | blue;
			    colorTable[i + table * 8] = rgb;
			}
			
			// update presets
			/*
			var r:int = 0;
			var c:int = 0;
			
			var time:int = getTimer();
			
			for(c = 0; c < CDG_FULL_WIDTH; ++c)
			{
				for(r = 0; r < CDG_FULL_HEIGHT; ++r)
				{
					buffer.setPixel(c, r, colorTable[indices[c][r]]);
				}
			}
			*/
			//trace("time: " + (getTimer() - time));
		}
		
		protected function tileBlock(packet:CDGPacket, bXor:Boolean):void
		{
			//trace("tileBlock(" + packet + ", " + bXor + ")");
					
			var color0:int, color1:int;
			var column_index:int, row_index:int;
			var byte:int, pixel:int, xor_col:int, currentColorIndex:int, new_col:int;
			
			color0 = packet.data[0] & 0x0F;
			color1 = packet.data[1] & 0x0F;
			row_index = ((packet.data[2] & 0x1F) * 12);
			column_index = ((packet.data[3] & 0x3F) * 6);
			
			////////trace("row_index: " + row_index);
			////////trace("column_index: "+ column_index);
			
			if (row_index > (CDG_FULL_HEIGHT - TILE_HEIGHT)) row_index = (CDG_FULL_HEIGHT - TILE_HEIGHT);
			if (column_index > (CDG_FULL_WIDTH - TILE_WIDTH)) column_index = (CDG_FULL_WIDTH - TILE_WIDTH);
			
			//  Set the pixel array for each of the pixels in the 12x6 tile.
			//  Normal = Set the color to either color0 or color1 depending
			//  on whether the pixel value is 0 or 1.
			//  XOR = XOR the color with the color index currently there.
			
			var i:int;
			var j:int;
			
			for (i = 0; i < 12; i++) 
			{
				byte = (packet.data[4 + i] & 0x3F);
				
				for (j = 0; j < 6; j++) 
				{
					pixel = (byte >> (5 - j)) & 0x01;
					
					if (bXor) 
					{
						// Tile Block XOR 
						if (pixel == 0) 
						{
							xor_col = color0;
						} 
						else 
						{
							xor_col = color1;
						}
			
						// Get the color index currently at this location, and xor with it 
						currentColorIndex = indices[column_index + j][row_index + i];
						
						new_col = currentColorIndex ^ xor_col;
					} 
					else 
					{
						if (pixel == 0) 
						{
							new_col = color0;
						} 
						else 
						{
							new_col = color1;
						}
					}
			
					// Set the pixel with the new color. We set both the surfarray
					// containing actual RGB values, as well as our array containing
					// the color indexes into our color table. 
					////////trace("preset.setPixel(" + (column_index + j) + ", " + (row_index + i) + ", " + new_col);
					indices[column_index + j][row_index + i] = new_col;      
					buffer.setPixel(column_index + j, row_index + i, colorTable[new_col]);      
				}
			}
		}
		
		protected function defineTransparentColor(packet:CDGPacket):void
		{
			//trace("defineTransparentColor(" + packet + ")");
			
			 transparentColor = packet.data[0] & 0x3F;
		}
		
		protected function scroll(packet:CDGPacket, copy:Boolean):void
		{
			//trace("scroll(" + packet + ")");
			
			var color:int, hScroll:int, vScroll:int;
			var hSCmd:int, hOffset:int, vSCmd:int, vOffset:int;
			var vScrollPixels:int, hScrollPixels:int;
			
			// Decode the scroll command parameters
			color  = packet.data[0] & 0x3F;
			hScroll = packet.data[1] & 0x3F;
			vScroll = packet.data[2] & 0x3F;
		
			hSCmd = (hScroll & 0x30) >> 4;
			hOffset = (hScroll & 0x07);
			vSCmd = (vScroll & 0x30) >> 4;
			vOffset = (vScroll & 0x0F);
		
			hOffset = hOffset < 5 ? hOffset : 5;
			vOffset = vOffset < 11 ? vOffset : 11;
		
			// Scroll Vertical - Calculate number of pixels
		
			vScrollPixels = 0;
			
			if (vSCmd == 2) 
			{
				vScrollPixels = - 12;
			} 
			else if (vSCmd == 1) 
			{
				vScrollPixels = 12;
			}
		
			// Scroll Horizontal- Calculate number of pixels
		
			hScrollPixels = 0;
			
			if (hSCmd == 2) 
			{
				hScrollPixels = - 6;
			} 
			else if (hSCmd == 1) 
			{
				hScrollPixels = 6;
			}
		
			if (hScrollPixels == 0 && vScrollPixels == 0) 
			{
				return;
			}
		
			// Perform the actual scroll.
		
			var temp:BitmapData = new BitmapData(CDG_FULL_HEIGHT, CDG_FULL_WIDTH);
			var vInc:int = vScrollPixels + CDG_FULL_HEIGHT;
			var hInc:int = hScrollPixels + CDG_FULL_WIDTH;
			var ri:int; // row index
			var ci:int; // column index
		
			for (ri = 0; ri < CDG_FULL_HEIGHT; ++ri) 
			{
				for (ci = 0; ci < CDG_FULL_WIDTH; ++ci) 
				{   
					temp.setPixel((ci + hInc) % CDG_FULL_WIDTH, (ri + vInc) % CDG_FULL_HEIGHT, buffer.getPixel(ci, ri));
				}
			}
		
			// if copy is false, we were supposed to fill in the new pixels
			// with a new color. Go back and do that now.
		
			if (!copy)
			{
				if (vScrollPixels > 0) 
				{
					for (ci = 0; ci < CDG_FULL_WIDTH; ++ci) 
					{
						for (ri = 0; ri < vScrollPixels; ++ri) {
							temp.setPixel(ci, ri, colorTable[color]);
						}
					}
				}
				else if (vScrollPixels < 0) 
				{
					for (ci = 0; ci < CDG_FULL_WIDTH; ++ci) 
					{
						for (ri = CDG_FULL_HEIGHT + vScrollPixels; ri < CDG_FULL_HEIGHT; ++ri) {
							temp.setPixel(ci, ri, colorTable[color]);
						}
					}
				}
				
				if (hScrollPixels > 0) 
				{
					for (ci = 0; ci < hScrollPixels; ++ci) 
					{
						for (ri = 0; ri < CDG_FULL_HEIGHT; ++ri) {
							temp.setPixel(ci, ri, colorTable[color]);
						}
					}
				} 
				else if (hScrollPixels < 0) 
				{
					for (ci = CDG_FULL_WIDTH + hScrollPixels; ci < CDG_FULL_WIDTH; ++ci) 
					{
						for (ri = 0; ri < CDG_FULL_HEIGHT; ++ri) {
							temp.setPixel(ci, ri, colorTable[color]);
						}
					}
				}
			}
		
			// Now copy the temporary buffer back to our array
		
			for (ri = 0; ri < CDG_FULL_HEIGHT; ++ri) 
			{
				for (ci = 0; ci < CDG_FULL_WIDTH; ++ci) 
				{
					buffer.setPixel(ci, ri, temp.getPixel(ci, ri));
				}
			}
		}
		
		public function render():void
		{
			var time:int = getTimer();
			
			output.copyPixels(buffer, buffer.rect, new Point(0, 0));
			/*
			//trace("render: " + (getTimer() - time));
			var ri:int;
			var ci:int;
			
			for(ri = 0; ri < CDG_FULL_HEIGHT; ++ri)
			{
				for(ci = 0; ci < CDG_FULL_WIDTH; ci++)
				{
					if(ri < TILE_HEIGHT || ri >= CDG_FULL_HEIGHT-TILE_HEIGHT || ci < TILE_WIDTH || ci >= CDG_FULL_WIDTH-TILE_WIDTH)
					{
						output.setPixel(ci, ri, colorTable[borderColorIndex]);
					}
					else
					{
						//////trace("setPixel(" + ci + ", " + ri + ", " + preset.getPixel(ci + hOffset, ri + vOffset));
						output.setPixel(ci, ri, buffer.getPixel(ci + hOffset, ri + vOffset));
					}
				}
			}
			*/
		}
	}
}