package;

import haxe.ds.Option;

typedef Action = {
	var frame:Int;
	var code:Int;
	var pressed:Bool;
}

class Video {
	//static var headerSize = 6 * 4;
	static var frameBitSize = 12;

	public var actions:Array<Action>;

	public var pauseFrame:Int = 0;
	
	public var initialDirections:Array<Bool> = [false, false, false, false]; // left, right, up, down

	private function getOption<T>(x:Option<T>):T {
		switch x {
			case None:
				throw "Invalid video string.";
			case Some(x):
				return x;
		}
	}

	public function new(?save:String) {
		actions = new Array();

		if (save == null) 
			return;

		// Load from save string
		var reader = new Bitstream.BSReader(save);

		initialDirections[0] = getOption(reader.readInt(1)) == 1;
		initialDirections[1] = getOption(reader.readInt(1)) == 1;
		initialDirections[2] = getOption(reader.readInt(1)) == 1;
		initialDirections[3] = getOption(reader.readInt(1)) == 1;

		pauseFrame = getOption(reader.readInt(frameBitSize));

		var actionsLength = getOption(reader.readInt(12));

		for (i in 0...actionsLength) {
			var frame = getOption(reader.readInt(frameBitSize));
			var code = getOption(reader.readInt(3));
			var pressed = getOption(reader.readInt(1));

			actions.push({frame: frame, code: code, pressed: pressed == 1});
		}
	}

	public function toString():String {
		var writer = new Bitstream.BSWriter();

		writer.writeInt(initialDirections[0] ? 1 : 0, 1);
		writer.writeInt(initialDirections[1] ? 1 : 0, 1);
		writer.writeInt(initialDirections[2] ? 1 : 0, 1);
		writer.writeInt(initialDirections[3] ? 1 : 0, 1);

		writer.writeInt(pauseFrame, frameBitSize);

		writer.writeInt(actions.length, 12);

		var lastFrame = 0;
		for (action in actions) {
			writer.writeInt(action.frame, frameBitSize);
			writer.writeInt(action.code, 3);
			writer.writeInt(action.pressed ? 1 : 0 , 1);
		}

		return writer.toString();
	}

	public static var keyCodes = [37, 38, 39, 40, 87]; // 37-40: Arrow keys, 87: W

	public static function toActionCode(keyCode:Int):Option<Int> {
		for (i in 0...keyCodes.length) {
			if (keyCodes[i] == keyCode)
				return Some(i);
		}
		return None;
	}

	public static function fromActionCode(actionCode:Int):Int {
		return keyCodes[actionCode];
	}

	public static function showActionCode(actionCode:Int):String {
		switch actionCode {
			case 0:
				return "Left   ";
			case 1 | 4:
				return "Up     ";
			case 2:
				return "Right  ";
			case 3:
				return "Down   ";
		}
		return "???    ";
	}

	public function copy():Video {
		var video = new Video();

		video.actions = actions.copy();

		video.pauseFrame = pauseFrame;

		video.initialDirections = initialDirections.copy();

		return video;
	}
}

class VideoRecorder {
	public var video:Video = new Video();

	private var keyStates:Array<Bool>;

	public function new(initialDirections:Array<Bool>) {
		keyStates = new Array();
		for (i in 0...Video.keyCodes.length) {
			keyStates.push(false);
		}

		video.initialDirections = initialDirections;
	}

	public function recordKey(frame:Int, keyCode:Int, pressed:Bool, silent:Bool) {
		switch Video.toActionCode(keyCode) {
			case Some(action):
				var oldState = keyStates[action];
				if (pressed == oldState)
					return;
				keyStates[action] = pressed;
				if (frame > 0)
					video.actions.push({frame: frame, code: action, pressed: pressed}); // can't record thing below frame 1
				if (!silent)
					trace('---> ${Video.showActionCode(action)} ${pressed ? "press  " : "unpress"} @ ${frame}');
			case None:
				return;
		}
	}

	public function saveVideo(frame:Int):Video {
		var res = video.copy();
		res.pauseFrame = frame;
		return res;
	}
}

class VideoPlayer {
	public var video:Video;

	public function new(video:Video) {
		this.video = video.copy();
	}

	public function getActions(frame:Int):Array<{code:Int, pressed:Bool}> {
		var res = [];
		while (video.actions.length > 0 && video.actions[0].frame == frame) {
			var action = video.actions.shift();
			res.push({code: Video.fromActionCode(action.code), pressed: action.pressed});
		}
		return res;
	}
}
