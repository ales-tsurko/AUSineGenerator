//
//  AUSineGeneratorDSPKernel.hpp
//  SineGenerator
//
//  Created by Ales Tsurko on 30.09.15.
//  Copyright © 2015 Ales Tsurko. All rights reserved.
//

#import "DSPKernel.hpp"
#import "ParameterRamper.hpp"

const float twopi = 2 * M_PI;

enum {
    SineGeneratorParamFrequency = 0,
    SineGeneratorParamAmplitude = 1
};

class AUSineGeneratorDSPKernel : public DSPKernel {
public:
    
    struct SineGen {
        float value = 0;
        double currentPhase;
        
        void calculateValueForPhase(float frequency, float amplitude, float phase, float sampleRate) {
            float cycleLength = sampleRate / frequency;
            
            value = sinf(twopi * (phase / cycleLength)) * amplitude;
        }
    };

    
    // MARK: Member Functions
    AUSineGeneratorDSPKernel() {}
    
    void init(int channelCount, double inSampleRate) {
        numberOfChannels = channelCount;
        sampleRate = float(inSampleRate);
        maxFrequency = 20000;
        reciprocalOfMaxFrequency = 1.0 / maxFrequency;
    }
    
    void setParameter(AUParameterAddress address, AUValue value) {
        switch (address) {
            case SineGeneratorParamFrequency:
                frequencyRamper.set(clamp(value * reciprocalOfMaxFrequency, 0.0f, 1.0f));
                break;
                
            case SineGeneratorParamAmplitude:
                amplitudeRamper.set(clamp(value, 0.0f, 1.0f));
                break;
        }
    }
    
    AUValue getParameter(AUParameterAddress address) {
        switch (address) {
            case SineGeneratorParamFrequency:
                // Return the goal. It is not thread safe to return the ramping value.
                return frequencyRamper.goal() * maxFrequency;
                
            case SineGeneratorParamAmplitude:
                return amplitudeRamper.goal();
                
            default: return 0.0f;
        }
    }
    
    void startRamp(AUParameterAddress address, AUValue value, AUAudioFrameCount duration) override {
        switch (address) {
            case SineGeneratorParamFrequency:
                frequencyRamper.startRamp(clamp(value * reciprocalOfMaxFrequency, 0.0f, 0.99f), duration);
                break;
                
            case SineGeneratorParamAmplitude:
                amplitudeRamper.startRamp(clamp(value, 0.0f, 1.0f), duration);
                break;
        }
    }
    
    void setOutputBuffer(AudioBufferList* outBufferList) {
        outBufferListPtr = outBufferList;
    }
    
    void process(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset) override {
        double phase = generator.currentPhase;
        
        for (int frameIndex = 0; frameIndex < frameCount; ++frameIndex) {
            float frequency = frequencyRamper.getStep() * maxFrequency;
            float amplitude = amplitudeRamper.getStep();
            float cycleLength = sampleRate / frequency;
            
            generator.calculateValueForPhase(frequency, amplitude, phase, sampleRate);
            
            for (int channel = 0; channel < numberOfChannels; ++channel) {
                float* out = (float*)outBufferListPtr->mBuffers[channel].mData;
                
                out[frameIndex] = generator.value;
            }
            
            phase++;
            if (phase > cycleLength) {
                phase-=cycleLength;
            }
        }
        
        generator.currentPhase = phase;
        
    }
    
    // MARK: Member Variables
    
private:
    SineGen generator;
    
    int numberOfChannels;
    float sampleRate = 44100;
    float maxFrequency;
    float reciprocalOfMaxFrequency;
    
    AudioBufferList* outBufferListPtr = nullptr;
    
public:
    
    // Parameters.
    ParameterRamper frequencyRamper = 440.0 / 44100.0;
    ParameterRamper amplitudeRamper = 0.99;
    
};
