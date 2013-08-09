/*
 * Copyright (c) 2013 Dan Wilcox <danomatika@gmail.com>
 *
 * BSD Simplified License.
 * For information on usage and redistribution, and for a DISCLAIMER OF ALL
 * WARRANTIES, see the file, "LICENSE.txt," in this distribution.
 *
 * See https://github.com/danomatika/PdParty for documentation
 *
 */
 #import "SceneManager.h"

#import <CoreMotion/CoreMotion.h>
#import "Log.h"
#import "Gui.h"
//#import "PdParser.h"
#import "AppDelegate.h"

#define ACCEL_UPDATE_HZ	60.0

@interface SceneManager () {
	
	CMMotionManager *motionManager; // for accel data
	
	//Osc *osc; // to send osc
	//PureData *pureData; // to set samplerate

	BOOL hasReshaped; // has the gui been reshaped?
}
@property (strong, readwrite, nonatomic) NSString* currentPath;
@property (assign, readwrite, getter=isRecording, nonatomic) BOOL recording;
@end

@implementation SceneManager

- (id)init {
	self = [super init];
	if(self) {
		
		hasReshaped = NO;
		
		// init motion manager
		motionManager = [[CMMotionManager alloc] init];
		
		// set osc and pure data pointer
		AppDelegate *app = (AppDelegate*)[[UIApplication sharedApplication] delegate];
		self.osc = app.osc;
		self.pureData = app.pureData;
		
		// create gui
		self.gui = [[Gui alloc] init];
	}
		
	return self;
}

- (BOOL)openScene:(NSString *)path withType:(SceneType)type forParent:(UIView *)parent andControls:(UIView *)controls {
	if([self.currentPath isEqualToString:path]) {
		DDLogVerbose(@"SceneManager openScene: ignoring scene with same path");
		return NO;
	}
	
	// create gui here as iPhone dosen't load view until *after* this is called
//	if(!self.gui) {
//		self.gui = [[Gui alloc] init];
//		self.gui.bounds = self.view.bounds;
//	}
	
	// close open scene
	[self closeScene];
	
	// open new scene
	switch(type) {
		case SceneTypePatch:
			self.scene = [PatchScene sceneWithParent:parent andGui:self.gui];
			break;
		case SceneTypeRj: {
			RjScene *rj = [RjScene sceneWithParent:parent andControls:controls];
			rj.dispatcher = self.pureData.dispatcher;
			self.scene = rj;
			break;
		}
		case SceneTypeDroid:
			self.scene = [DroidScene sceneWithParent:parent andGui:self.gui];
			break;
		case SceneTypeParty:
			self.scene = [PartyScene sceneWithParent:parent andGui:self.gui];
			break;
		default: // SceneTypeEmpty
			self.scene = [[Scene alloc] init];
			break;
	}
	self.pureData.audioEnabled = YES;
	self.pureData.sampleRate = self.scene.sampleRate;
	//self.enableAccelerometer = self.scene.requiresAccel;
	//self.enableRotation = self.scene.requiresRotation;
	//self.enableKeyGrabber = self.scene.requiresKeys;
	self.pureData.playing = YES;
	[self.scene open:path];
	
	// turn up volume & turn on transport, update gui
	[self.pureData sendCurrentPlayValues];
//	[self updateRjControls];
//	
//	// set nav controller title
//	self.navigationItem.title = self.scene.name;
//	
//	// hide iPad browser popover on selection 
//	if(self.masterPopoverController != nil) {
//        [self.masterPopoverController dismissPopoverAnimated:YES];
//    }
	
	// store current location
	self.currentPath = path;
	
	return YES;
}

- (void)closeScene {
	if(self.scene) {
		if(self.pureData.isRecording) {
			[self.pureData stopRecording];
//			[self.rjRecordButton setTitle:@"Record" forState:UIControlStateNormal];
		}
		[self.scene close];
		self.scene = nil;
	}
}

- (void)reshapeWithFrame:(CGRect)frame {
	
	self.gui.bounds = frame;
		
	// do animations if gui has already been setup once
	// http://www.techotopia.com/index.php/Basic_iOS_4_iPhone_Animation_using_Core_Animation
	if(hasReshaped) {
		[UIView beginAnimations:nil context:nil];
	}
	[self.scene reshape];
	if(hasReshaped) {
		[UIView commitAnimations];
	}
	else {
		hasReshaped = YES;
	}
}

- (void)updateParent:(UIView *)parent andControls:(UIView *)controls {
	if(!self.scene) return;
	self.scene.parentView = parent;
	if(self.scene.type == SceneTypeRj) {
		((RjScene*) self.scene).controlsView = controls;
	}
	//[self reshapeWithFrame:self.scene.parent.frame];
}

#pragma mark Send Events

- (void)sendTouch:(NSString *)eventType forId:(int)id atX:(float)x andY:(float)y {
	[PureData sendTouch:eventType forId:id atX:x andY:y];
	if(self.osc.isListening) {
		[self.osc sendTouch:eventType forId:id atX:x andY:y];
	}
}

- (void)sendRotate:(float)degrees newOrientation:(NSString *)orientation {
	if(self.scene.requiresRotation) {
		[PureData sendRotate:degrees newOrientation:orientation];
	}
	if(self.osc.isListening) {
		[self.osc sendRotate:degrees newOrientation:orientation];
	}
}

// pd key event
- (void)sendKey:(int)key {
	if(self.scene.requiresKeys) {
		[PureData sendKey:key];
	}
	if(self.osc.isListening) {
		[self.osc sendKey:key];
	}
}

#pragma mark Overridden Getters / Setters

- (void)setEnableAccelerometer:(BOOL)enableAccelerometer {
	if(self.enableAccelerometer == enableAccelerometer) {
		return;
	}
	_enableAccelerometer = enableAccelerometer;
	
	// start
	if(enableAccelerometer) {
		if([motionManager isAccelerometerAvailable]) {
			NSTimeInterval updateInterval = 1.0/ACCEL_UPDATE_HZ;
			[motionManager setAccelerometerUpdateInterval:updateInterval];
			
			// accel data callback block
			[motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue]
				withHandler:^(CMAccelerometerData *accelerometerData, NSError *error) {
//					DDLogVerbose(@"accel %f %f %f", accelerometerData.acceleration.x,
//													accelerometerData.acceleration.y,
//													accelerometerData.acceleration.z);
					[PureData sendAccel:accelerometerData.acceleration.x
									  y:accelerometerData.acceleration.y
									  z:accelerometerData.acceleration.z];
					if(self.osc.isListening) {
						[self.osc sendAccel:accelerometerData.acceleration.x
										  y:accelerometerData.acceleration.y
										  z:accelerometerData.acceleration.z];
					}
				}];
		}
		DDLogVerbose(@"SceneManager: enabled accel");
	}
	else { // stop
		if([motionManager isAccelerometerActive]) {
          [motionManager stopAccelerometerUpdates];
		}
		DDLogVerbose(@"SceneManager: disabled accel");
	}
}

#pragma mark Controls

//- (void)setPlaying:(BOOL)playing {
//	self.pureData.audioEnabled = playing;
//}
//
//- (BOOL)isPlaying {
//	return self.pureData.audioEnabled;
//}
//
//- (BOOL)startRecording {
//	NSString *recordDir = [[Util documentsPath] stringByAppendingPathComponent:@"recordings"];
//	if(![[NSFileManager defaultManager] fileExistsAtPath:recordDir]) {
//		DDLogVerbose(@"Recordings dir not found, creating %@", recordDir);
//		NSError *error;
//		if(![[NSFileManager defaultManager] createDirectoryAtPath:recordDir withIntermediateDirectories:NO attributes:nil error:&error]) {
//			DDLogError(@"Couldn't create %@, error: %@", recordDir, error.localizedDescription);
//			return;
//		}
//	}
//	
//	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
//	[formatter setDateFormat:@"yy-MM-dd_hhmmss"];
//	NSString *date = [formatter stringFromDate:[NSDate date]];
//	[pureData startRecordingTo:[recordDir stringByAppendingPathComponent:[self.scene.name stringByAppendingFormat:@"_%@.wav", date]]];
//}

@end