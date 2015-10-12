//
//  AUSineGeneratorDSPKernel.hpp
//  SineGenerator
//
//  Created by Ales Tsurko on 30.09.15.
//  Copyright © 2015 Ales Tsurko. All rights reserved.
//

#import "DSPKernel.hpp"
#import "ParameterRamper.hpp"
#include <Accelerate/Accelerate.h>

const float twopi = 2 * M_PI;

enum {
    SineGeneratorParamFrequency = 0,
    SineGeneratorParamAmplitude = 1
};

class AUSineGeneratorDSPKernel : public DSPKernel {
private:
    // MARK: Member Variables
    static const int tableSize = 1<<16;
    float* sineTable = new float[tableSize+1];
    float incr = 0.0;
    
    int numberOfChannels;
    float sampleRate = 44100.0;
    float maxFrequency;
    float reciprocalOfMaxFrequency;
    
    AudioBufferList* outBufferListPtr = nullptr;
    
    void fillSineTable() {
        int tabLength = tableSize;
        float initValue = 0;
        float incr = 1.0;
        float phaseStep = twopi / float(tabLength);
        
        vDSP_vramp(&initValue, &incr, sineTable, 1, vDSP_Length(tabLength));
        vDSP_vsmul(sineTable, 1, &phaseStep, sineTable, 1, vDSP_Length(tabLength));
        vvsinf(sineTable, sineTable, &tabLength);
    }
    
public:
    // Parameters.
    ParameterRamper frequencyRamper = 440.0 / 44100.0;
    ParameterRamper amplitudeRamper = 0.99;
    
    // MARK: Member Functions
    AUSineGeneratorDSPKernel() {}
    
    void init(int channelCount, double inSampleRate) {
        numberOfChannels = channelCount;
        sampleRate = float(inSampleRate);
        maxFrequency = 20000;
        reciprocalOfMaxFrequency = 1.0 / maxFrequency;
        fillSineTable();
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
                return frequencyRamper.goal() * maxFrequency;
                
            case SineGeneratorParamAmplitude:
                return amplitudeRamper.goal();
                
            default: return 0.0f;
        }
    }
    
    void startRamp(AUParameterAddress address, AUValue value, AUAudioFrameCount duration) override {
        switch (address) {
            case SineGeneratorParamFrequency:
                frequencyRamper.startRamp(clamp(value * reciprocalOfMaxFrequency, 0.0f, 1.0f), duration);
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
        for (int frameIndex = 0; frameIndex < frameCount; ++frameIndex) {
            float frequency = frequencyRamper.getStep() * maxFrequency;
            float amplitude = amplitudeRamper.getStep();
            float sampleLength = frequency / sampleRate;
            
            incr += sampleLength;
            incr -= floorf(incr);
            
            float index = float(tableSize) * incr;
            float decimal = float(index) - floorf(float(index));
            
            float a0 = sineTable[int(index)];
            float a1 = sineTable[int(index) + 1];
            
            float value = amplitude * (a0 + decimal * (a1 - a0));
            
            for (int channel = 0; channel < numberOfChannels; ++channel) {
                float* out = (float*)outBufferListPtr->mBuffers[channel].mData;
                
                out[frameIndex] = value;
            }
        }
    }
};
