package;

import haxe.Json;
import KeyBindings;
import js.Browser;
import haxe.ds.Option;

class PlayControl {
	public var frame:Int = 0; // Frames since level start. Inputs do happen on frame 0!
	public var paused:Bool = false; // If true, wait for frame advance to run.
	public var speed:Int = 0; // 0 for slow, 1 for normal, 2 for fast forward.
	public var silent:Bool = false; // Hide input messages

	public function new() {}

	public function pause() {
		paused = true;
		speed = 0;
	}
}

class Engine {
	var frameLengthDecimalPlaces = 8;
	var frameLength:Float = 16.66666666;

	// Directions in order: Left, right, up, down
	var initialDirections:Array<Bool> = [false, false, false, false];

	var control = new PlayControl();
	var playback:Option<Video.VideoPlayer> = None; // If this is initialized, we're in playback.
	var recording:Video.VideoRecorder = new Video.VideoRecorder([false, false, false, false]);
	var slots:Array<Video>;

	var fullgameVideo:Dynamic = null;
	var fullgameLevelCounter:Int = 0;

	var pausedCallback:Option<Dynamic> = None;
	var fakeTime:Float = 0;
	var _requestAnimationFrame:Dynamic;
	var _now:Dynamic;

	

	public function new() {
		// Inject our methods into the global scope.
		_requestAnimationFrame = Browser.window.requestAnimationFrame;
		_now = Browser.window.performance.now;
		untyped window.requestAnimationFrame = this.requestAnimationFrame;
		untyped window.performance.now = function() {
			return fakeTime;
		}
		fakeTime = _now();

		// hook into the helper script
		untyped window.coffee = {};
		untyped window.coffee._onScene = onScene;

		untyped window.coffee._keyup = this.keyup;
		untyped window.coffee._keydown = this.keydown;

		// API for runners
		untyped window.coffee.load = function(string:String, ?slot:Int) {
			if (slot == null || slot > 9 || slot < 0)
				slot = 0;
			slots[slot] = new Video(string);
		}

		untyped window.coffee.loadFullGame = function(strings:Array<String>) {
			fullgameVideo = strings.map(function(videoString) {
				return new Video(videoString);
			});

			// Run the game on normal speed, because TAS commands are disabled in "full-game" mode
			control.speed = 1;
			control.paused = false;
			triggerPausedCallback();

			// Prepare initial inputs for the first level. It is assumed the "loadFullGame" function is called in the main menu.
			initialDirections = fullgameVideo[0].initialDirections.slice();
			primeControls(true);
		}

		untyped window.coffee.clearFullGame = function(string:String) {
			fullgameVideo = null;
		}

		untyped window.coffee.initialLeft = function(pressed:Bool) {
			initialDirections[0] = pressed;
		}
		untyped window.coffee.initialRight = function(pressed:Bool) {
			initialDirections[1] = pressed;
		}
		untyped window.coffee.initialUp = function(pressed:Bool) {
			initialDirections[2] = pressed;
		}
		untyped window.coffee.initialDown = function(pressed:Bool) {
			initialDirections[3] = pressed;
		}

		slots = new Array();
		for (i in 0...10) {
			slots.push(new Video());
		}

		control.speed = 1;
	}

	function wrapCallback(callback:Dynamic) {
		return function() {
			switch playback {
				case Some(player):
					for (action in player.getActions(control.frame)) {
						sendGameInput(action.code, action.pressed);
					}

					// playback for the current level has ended
					if (control.frame + 1 >= player.video.pauseFrame) {
						// If we are not in full game playback, pause at the last frame of a video
						if (fullgameVideo == null) {
							
							control.pause();
							trace('[PAUSE ] @ ${control.frame + 1}');
							control.silent = false;
						} 
						// For fullgame playback, prime the initial direction controls for the next level
						else {
							if (fullgameLevelCounter >= 1 && fullgameLevelCounter < fullgameVideo.length) {
								initialDirections = fullgameVideo[fullgameLevelCounter].initialDirections.slice();
							}
							// If there is no next level to play, unpress all the initial direction controls
							else{
								initialDirections = [false, false, false, false];
							}

							control.frame = 0;
							primeControls(true);
						}  
							
						playback = None;
					}
				case None:
					{}
			}

			fakeTime += frameLength;
			callback(fakeTime);

			control.frame += 1;
		}
	}

	function requestAnimationFrame(callback:Dynamic) {
		var wrappedCallback = wrapCallback(callback);
		if (!control.paused) {
			switch control.speed {
				case 0:
					Browser.window.setTimeout(wrappedCallback, 100);
				case 1:
					_requestAnimationFrame(wrappedCallback);
				case _:
					Browser.window.setTimeout(wrappedCallback, 0);
			}
		} else {
			pausedCallback = Some(wrappedCallback);
		}
	}

	function triggerPausedCallback() {
		switch pausedCallback {
			case Some(cb):
				pausedCallback = None;
				cb();
			case None:
				{}
		}
	}

	var keyupHandler:Dynamic;
	var keydownHandler:Dynamic;

	function keyup(callback:Dynamic) {
		keyupHandler = callback;
		Browser.window.onkeyup = function(key) {
			onKey(key, false);
		}
	}

	function keydown(callback:Dynamic) {
		keydownHandler = callback;
		Browser.window.onkeydown = function(key) {
			onKey(key, true);
		}
	}

	// Top-level for keyboard input from the user.
	function onKey(event:Dynamic, pressed:Bool) {
		if (!Util.isSome(playback)) {
			// We're not in playback, so we should pass through keys.

			// Prevent pressing a/s/d/z and r. 
			// Also prevent pressing "1", it automatically send you to level 1, no matter where you are in the game.
			var suppress = [83, 65, 68, 82, 90, 49]; 

			if (suppress.indexOf(event.keyCode) == -1)
				sendGameInput(event.keyCode, pressed);
		}
		if (pressed && fullgameVideo == null) {
			switch (KeyBindings.fromKeyCode(event.keyCode)) {
				case Some(input):
					if (handleInterfaceInput(input, event.ctrlKey, event.altKey)) {
						event.preventDefault();
					}
				case _:
					{}
			}
		}
	}

	// Send input to the game and record it.
	function sendGameInput(keyCode:Int, pressed:Bool) {
		recording.recordKey(control.frame, keyCode, pressed, control.silent);
		var event = {
			which: keyCode, 
			key: KeyCodes.toKey(keyCode), 
			preventDefault: function() {},
			stopPropagation: function () {}
		};

		if (pressed) {
			keydownHandler(event);
		} else {
			keyupHandler(event);
		}
	}

	function primeControls(buffer:Bool) {
		for (code in Video.keyCodes) {
			sendGameInput(code, false);
		}

		var initialInputsLog = "";

		if (initialDirections[0]) {
			initialInputsLog += " LEFT";
			sendGameInput(37, true);
		}
		if (initialDirections[1]) {
			initialInputsLog += " RIGHT";
			sendGameInput(39, true);
		}
		if (initialDirections[2]) {
			initialInputsLog += " UP";
			sendGameInput(38, true);
		}
		if (initialDirections[3]) {
			initialInputsLog += " DOWN";
			sendGameInput(40, true);
		}

		if (buffer && initialInputsLog != ""){
			trace('---> Initial buttons: ' + initialInputsLog);
		}
	}

	function resetLevel(?slot:Int, ?replay:Bool) {
		if (replay == null)
			replay = false;
		trace('[${replay ? "REPLAY" : "RESET to"} ${(slot == null) ? "start" : "slot " + Std.string(slot) + "..."}] @ 1');

		// Press the "r" key to trigger in-game reset
		sendGameInput(82, true);
		sendGameInput(82, false);

		// Create a new instance of video-recorder only when there is no save-slot replay.
		// Otherwise, the "loadPlayback" function will take care of it.
		if (slot == null) {
			recording = new Video.VideoRecorder(initialDirections);
		}
		
		control = new PlayControl();
		primeControls(true);
	}

	function loadPlayback(video:Video) {
		playback = Some(new Video.VideoPlayer(video));
		initialDirections = video.initialDirections.copy();
		recording = new Video.VideoRecorder(initialDirections);
	}

	// Keyboard interface.
	// Return true to signal that input was captured.
	function handleInterfaceInput(input:KeyBindings.CoffeeInput, ctrlKey:Bool, altKey:Bool):Bool {
		var oldControl = untyped JSON.parse(JSON.stringify(control));

		// stepping frames
		if (input == CoffeeInput.StepFrame && control.paused) {
			triggerPausedCallback();
			trace('[STEP  ] @ ${control.frame}');
			return true;
		}

		// pausing
		if (input == CoffeeInput.Pause) {
			if (!oldControl.paused)
				trace('[PAUSE ] @ ${control.frame + 1}');
			control.pause();
			return true;
		}

		// changing playback speed
		{
			var playAction = true;
			switch (input) {
				case CoffeeInput.PlaySlow:
					control.speed = 0;
				case CoffeeInput.PlayNormal:
					control.speed = 1;
				case CoffeeInput.PlayFast:
					control.speed = 2;
				case _:
					playAction = false;
			}
			if (playAction) {
				control.paused = false;
				if (oldControl.paused)
					trace('[PLAY  ] @ ${control.frame}');

				triggerPausedCallback();
				return true;
			}
		}

		// r to reset level
		if (input == CoffeeInput.Reset) {
			playback = None;
			resetLevel();
			control.pause();
			triggerPausedCallback();
			return true;
		}

		// Enter to replay the video in slot 0 at normal speed
		if (input == CoffeeInput.Replay) {
			resetLevel(0, true);
			loadPlayback(slots[0]);
			control.speed = 1;
			triggerPausedCallback();
			return true;
		}

		// handling slots
		switch (input) {
			case CoffeeInput.Slot(slot):
				// replay slot
				if (!ctrlKey) {
					resetLevel(slot);
					loadPlayback(slots[slot]);
					control.speed = 2;
					control.silent = true;

					if (altKey) {
						control.pause();
						control.silent = false;
					}
					
					triggerPausedCallback();
					return true;
				}

				// with ctrl: save slot
				if (ctrlKey && !altKey) {
					control.pause();
					var video = recording.saveVideo(control.frame);
					trace('[SAVE slot ${slot}] @ ${control.frame}');
					trace('Data: ${video.toString()}');
					slots[slot] = video;
					return true;
				}
			case _:
				{}
		}
		return false;
	}

	function onScene(levelNum:Int) {
		// Function that is called when a level in the game is loaded.
		// This function is called from the game code itself.
		
		// Ignore "level -1", not sure why this parameter is sent sometimes
		if (levelNum == -1) return;

		trace('[SCENE ${levelNum}]');

		// We are not in full game playback, so nothing to do here
		if (fullgameVideo == null)
			return;

		// We enter the main menu, prepare inputs for the first level.
		if (levelNum == 0){
			initialDirections = fullgameVideo[0].initialDirections.slice();
			primeControls(true);
			return;
		}

		// Prepare a video playback for the current level as the player enters it
		if (levelNum >= 1 && levelNum <= fullgameVideo.length) {
			fullgameLevelCounter = levelNum;
			loadPlayback(fullgameVideo[fullgameLevelCounter - 1]);
			control.paused = false;
			control.frame = 0;
			control.speed = 1;
			//primeControls(true);
		}
	}

	function truncateFloat(number:Float, digits:Int):Float {
		var re = new EReg("(\\d+\\.\\d{" + digits + "})(\\d)", "i");
		var isMatched = re.match(Std.string(number));
		if (isMatched){
			return Std.parseFloat(re.matched(1));
		}
		else return number;
	}
}
