//
//  ModalViewController.swift
//  HTTPSwiftExample
//
//  Created by UbiComp on 11/15/21.
//  Copyright © 2021 Eric Larson. All rights reserved.
//

import UIKit

class ModalViewController: UIViewController, UITextFieldDelegate,UIPickerViewDelegate,UIPickerViewDataSource {
    
    var delegate:ModalDelegate?

    var models = ["SVM", "KNN", "Compare"]
    
    @IBOutlet weak var ModelPicker: UIPickerView!
    @IBOutlet weak var parameterLabel: UILabel!
    @IBOutlet weak var parameterTextField: UITextField!
    
    @IBOutlet weak var parameter2Label: UILabel!
    @IBOutlet weak var parameter2TextField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.ModelPicker.delegate = self
        self.ModelPicker.dataSource = self
        
        self.ModelPicker.selectRow(0, inComponent: 0, animated: true)
        self.parameterLabel.text = "Penalty Number"
        self.parameter2Label.text = "N/A"
        // Do any additional setup after loading the view.
    }
    

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
            return 1
        }
        
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return models.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        print(models[row])
        return models[row]
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if let name = models[row] as? String {
            var textFText = ""
            var text2Text = ""
            
            switch name {
            case "SVM":
                textFText = "Penalty Number"
                text2Text = "N/A"
            case "KNN":
                textFText = "Number of Neighbors"
                text2Text = "N/A"
            case "Compare":
                textFText = "Number of Neighbors"
                text2Text = "Penalty Number"
            default:
                textFText = "N/A"
                text2Text = "N/A"
            }

            DispatchQueue.main.async {
                self.parameterLabel.text = textFText
                self.parameter2Label.text = text2Text
            }
            
        }
    }
    
    @IBAction func submitParameters(_ sender: Any) {
        let modelType = self.ModelPicker.selectedRow(inComponent: 0)
        var params:[Int] = []
        params.append(Int(parameterTextField.text!) ?? -999)
        if modelType == 2 {
            params.append(Int(parameter2TextField.text!) ?? -999)
        }
        
        parameterTextField.resignFirstResponder()
        parameter2TextField.resignFirstResponder()
        
        if let delegate = delegate {
            delegate.setParametersAndTrain(modelType: modelType, withParameters: params)
        }
        dismiss(animated: true, completion: nil)
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
