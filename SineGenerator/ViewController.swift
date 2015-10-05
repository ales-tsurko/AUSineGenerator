//
//  ViewController.swift
//  SineGenerator
//
//  Created by Ales Tsurko on 30.09.15.
//  Copyright © 2015 Ales Tsurko. All rights reserved.
//

import UIKit
import AVFoundation
import AUSineGeneratorFramework

class ViewController: UIViewController {
    
    @IBOutlet var frequencySlider: UISlider!
    @IBOutlet var amplitudeSlider: UISlider!
    @IBOutlet var frequencyValueLabel: UILabel!
    @IBOutlet var amplitudeValueLabel: UILabel!
    
    var frequencyParameter: AUParameter!
    var amplitudeParameter: AUParameter!
    
    var audioUnit: AUSineGenerator!
    let engine = AVAudioEngine()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
            
            AVAudioUnitGenerator.instantiateWithComponentDescription(AUSineGenerator.audioComponentDescription(), options: []) {
                audioUnit, error in
                
                guard audioUnit != nil else {
                    print("failed")
                    return
                }
                
                self.audioUnit = audioUnit!.AUAudioUnit as! AUSineGenerator
                
                self.engine.attachNode(audioUnit!)
                self.engine.connect(audioUnit!, to: self.engine.mainMixerNode, format: self.audioUnit!.format)
                
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    try self.engine.start()
                } catch {
                    print("Error: \(error)")
                }
            }
            
        } catch {
            print("Error: \(error)")
        }
        
        linkParametersWithGUI()
    }
    
    func linkParametersWithGUI() {
        guard let paramTree = self.audioUnit!.parameterTree else { return }
        
        self.frequencyParameter = paramTree.valueForKey("frequency") as? AUParameter
        self.amplitudeParameter = paramTree.valueForKey("amplitude") as? AUParameter
        
        self.frequencySlider.minimumValue = self.frequencyParameter.minValue
        self.frequencySlider.maximumValue = self.frequencyParameter.maxValue
        self.amplitudeSlider.minimumValue = self.amplitudeParameter.minValue
        self.amplitudeSlider.maximumValue = self.amplitudeParameter.maxValue
        
        paramTree.tokenByAddingParameterObserver{
            address, value in
            dispatch_async(dispatch_get_main_queue()) {
                if address == self.frequencyParameter.address {
                    self.frequencySlider.value = self.frequencyParameter.value
                    self.frequencyValueLabel.text = self.frequencyParameter.stringFromValue(nil)
                }
                else if address == self.amplitudeParameter.address {
                    self.amplitudeSlider.value = self.amplitudeParameter.value
                    self.amplitudeValueLabel.text = self.amplitudeParameter.stringFromValue(nil)
                }
            }
        }
        
        frequencySlider.value = frequencyParameter.value
        amplitudeSlider.value = amplitudeParameter.value
        frequencyValueLabel.text = frequencyParameter.stringFromValue(nil)
        amplitudeValueLabel.text = amplitudeParameter.stringFromValue(nil)
    }

    @IBAction func frequencySliderAction(sender: UISlider) {
        frequencyParameter.value = sender.value
    }

    @IBAction func amplitudeSliderAction(sender: UISlider) {
        amplitudeParameter.value = sender.value
    }
}

