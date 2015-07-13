package com.newgonzo.cdg
{
	import flash.utils.ByteArray;
	
	public class CDGPacket
	{
		public var command:int = 0;
		public var instruction:int = 0;
		public var parityQ:ByteArray = new ByteArray();
		public var data:ByteArray = new ByteArray();
		public var parityP:ByteArray = new ByteArray();
		
		public function CDGPacket()
		{
		}


		public function toString():String
		{
			var s:String = "";
			var len:int = data.length;
			var i:int = 0;
			
			while(i < len)
			{
				s += int(data[i]).toString(16);
				i++;
			}
			
			return s;
		}
	}
}