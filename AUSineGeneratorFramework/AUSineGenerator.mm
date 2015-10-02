//
//  AUSineGenerator.m
//  SineGenerator
//
//  Created by Ales Tsurko on 30.09.15.
//  Copyright © 2015 Ales Tsurko. All rights reserved.
//

#import "AUSineGenerator.h"
#import <AVFoundation/AVFoundation.h>
#import "AUSineGeneratorDSPKernel.hpp"

const double SAMPLE_RATE = 44100.0;
const AVAudioChannelCount NUM_OF_CHANNELS = 2;
const AUValue minFrequency = 110;
const AUValue maxFrequency = 1760;

@interface AUSineGenerator ()

@property AUAudioUnitBus *outputBus;
@property AUAudioUnitBusArray *outputBusArray;

@property (nonatomic, readwrite) AUParameterTree *parameterTree;

@end

@implementation AUSineGenerator {
    AUSineGeneratorDSPKernel _kernel;
}

@synthesize parameterTree = _parameterTree;

+ (AudioComponentDescription)audioComponentDescription {
    AudioComponentDescription acd = {
        .componentType = kAudioUnitType_Generator,
        .componentSubType = 'sine',
        .componentManufacturer = 'AlsC',
        .componentFlags = 0,
        .componentFlagsMask = 0,
    };
    return acd;
}

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self registerSubclass:[AUSineGenerator class]
        asComponentDescription:[self audioComponentDescription]
                          name:@"AUSineGenerator"
                       version:UINT32_MAX];
    });
}

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription options:(AudioComponentInstantiationOptions)options error:(NSError **)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    
    if (self == nil) {
        return nil;
    }
    
    // Initialize a default format for the busses.
    self.format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:SAMPLE_RATE channels:NUM_OF_CHANNELS];
    
    // Create a DSP kernel to handle the signal processing.
    _kernel.init(self.format.channelCount, self.format.sampleRate);
    
    // Create a parameter object for the frequency.
    AUParameter *frequencyParam = [AUParameterTree createParameterWithIdentifier:@"frequency"
                                                                            name:@"Frequency"
                                                                         address:SineGeneratorParamFrequency
                                                                             min:minFrequency
                                                                             max:maxFrequency
                                                                            unit:kAudioUnitParameterUnit_Hertz
                                                                        unitName:nil
                                                                           flags:0
                                                                    valueStrings:nil
                                                             dependentParameters:nil];
    
    // Create a parameter object for the amplitude.
    AUParameter *amplitudeParam = [AUParameterTree createParameterWithIdentifier:@"amplitude"
                                                                            name:@"Amplitude"
                                                                         address:SineGeneratorParamAmplitude
                                                                             min:0.0
                                                                             max:1.0
                                                                            unit:kAudioUnitParameterUnit_Generic
                                                                        unitName:nil
                                                                           flags:0
                                                                    valueStrings:nil
                                                             dependentParameters:nil];
    
    // Initialize the parameter values.
    frequencyParam.value = 440.0;
    amplitudeParam.value = 0.99;
    _kernel.setParameter(SineGeneratorParamFrequency, frequencyParam.value);
    _kernel.setParameter(SineGeneratorParamAmplitude, amplitudeParam.value);
    
    // Create the parameter tree.
    _parameterTree = [AUParameterTree createTreeWithChildren:@[frequencyParam, amplitudeParam]];
    
    // Create the output bus.
    _outputBus = [[AUAudioUnitBus alloc] initWithFormat:self.format error:nil];
    
    // Create the output bus array.
    _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeOutput busses: @[_outputBus]];
    
    // Make a local pointer to the kernel to avoid capturing self.
    __block AUSineGeneratorDSPKernel *sineGeneratorKernel = &_kernel;
    
    // implementorValueObserver is called when a parameter changes value.
    _parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
        sineGeneratorKernel->setParameter(param.address, value);
    };
    
    // implementorValueProvider is called when the value needs to be refreshed.
    _parameterTree.implementorValueProvider = ^(AUParameter *param) {
        return sineGeneratorKernel->getParameter(param.address);
    };
    
    // A function to provide string representations of parameter values.
    _parameterTree.implementorStringFromValueCallback = ^(AUParameter *param, const AUValue *__nullable valuePtr) {
        AUValue value = valuePtr == nil ? param.value : *valuePtr;
        
        switch (param.address) {
            case SineGeneratorParamFrequency:
                return [NSString stringWithFormat:@"%.f", value];
                
            case SineGeneratorParamAmplitude:
                return [NSString stringWithFormat:@"%.3f", value];
                
            default:
                return @"?";
        }
    };
    
    self.maximumFramesToRender = 512;
    
    return self;
}

#pragma mark - AUAudioUnit Overrides

- (AUAudioUnitBusArray *)outputBusses {
    return _outputBusArray;
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) {
        return NO;
    }
    
    _kernel.init(self.outputBus.format.channelCount, self.outputBus.format.sampleRate);
    
    // There is a bug with this code when using scheduleParameter. The same bug in the Apple's FilterDemoApp.
    // I use startRamp of the kernel instead of scheduleParameter to prevent this problem.
    /*
     While rendering, we want to schedule all parameter changes. Setting them
     off the render thread is not thread safe.
     */
//    __block AUScheduleParameterBlock scheduleParameter = self.scheduleParameterBlock;
    
    // Ramp over 10 milliseconds.
    __block AUAudioFrameCount rampTime = AUAudioFrameCount(0.01 * self.outputBus.format.sampleRate);
    
//    self.parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
//        scheduleParameter(AUEventSampleTimeImmediate, rampTime, param.address, value);
//    };
    
    __block AUSineGeneratorDSPKernel *sineGeneratorKernel = &_kernel;
    self.parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
        sineGeneratorKernel->startRamp(param.address, value, rampTime);
    };
    
    return YES;
}

- (void)deallocateRenderResources {
    [super deallocateRenderResources];
    
    // Make a local pointer to the kernel to avoid capturing self.
    __block AUSineGeneratorDSPKernel *sineGeneratorKernel = &_kernel;
    
    // Go back to setting parameters instead of scheduling them.
    self.parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
        sineGeneratorKernel->setParameter(param.address, value);
    };
}

- (AUInternalRenderBlock)internalRenderBlock {
    /*
     Capture in locals to avoid ObjC member lookups. If "self" is captured in
     render, we're doing it wrong.
     */
    __block AUSineGeneratorDSPKernel *state = &_kernel;
    __block AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:self.format frameCapacity:self.maximumFramesToRender];
    
    return ^AUAudioUnitStatus(
                              AudioUnitRenderActionFlags *actionFlags,
                              const AudioTimeStamp       *timestamp,
                              AVAudioFrameCount           frameCount,
                              NSInteger                   outputBusNumber,
                              AudioBufferList            *outputData,
                              const AURenderEvent        *realtimeEventListHead,
                              AURenderPullInputBlock      pullInputBlock) {
        
        /*
         If the caller passed non-nil output pointers, use those. Otherwise,
         process in-place in the input buffer. If your algorithm cannot process
         in-place, then you will need to preallocate an output buffer and use
         it here.
         */
        AudioBufferList *outAudioBufferList = outputData;
        if (outAudioBufferList->mBuffers[0].mData == nullptr) {
            for (UInt32 i = 0; i < outAudioBufferList->mNumberBuffers; ++i) {
                outAudioBufferList->mBuffers[i].mData = buffer.mutableAudioBufferList->mBuffers[i].mData;
            }
        }
        
        state->setOutputBuffer(outAudioBufferList);
        state->processWithEvents(timestamp, frameCount, realtimeEventListHead);
        
        return noErr;
    };
}


@end
