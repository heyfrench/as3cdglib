# Introduction
ActionScript 3.0 library for parsing and displaying karaoke (CDG) files. Mostly works, but there are a few artifacts during playback. For reference use only.

## Example use

```as3
import com.springbox.cdg.CDGFile;
			
private var loader:URLLoader;
private var sound:Sound;
private var channel:SoundChannel;
private var cdg:CDGFile;

private var pos:Number;
private var bitmap:Bitmap;

protected function creationComplete():void
{
	loader = new URLLoader();
	loader.dataFormat = URLLoaderDataFormat.BINARY;
	loader.addEventListener(Event.COMPLETE, cdgLoadComplete);
	loader.load(new URLRequest("karaoke.cdg"));
	
}

private function cdgLoadComplete(event:Event):void
{
	var bytes:ByteArray = loader.data as ByteArray;
	
	cdg = new CDGFile(bytes);
	
	bitmap = new Bitmap(cdg.image);
	bitmap.x = 0;
	bitmap.y = 0;
	
	stage.addChild(bitmap);
	
	loadMP3();
}

protected function loadMP3():void
{
	sound = new Sound(new URLRequest("song.mp3"));
	channel = sound.play();
	
	start();
}

protected function start():void
{
	addEventListener(Event.ENTER_FRAME, enterFrame);
}

private function enterFrame(event:Event):void
{
	if(!channel) return;
	
	cdg.renderPosition(channel.position);
}
```