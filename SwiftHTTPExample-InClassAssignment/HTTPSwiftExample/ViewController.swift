//
//  ViewController.swift
//  HTTPSwiftExample
//
//  Created by Ubicomp on 11/6/21
//

// This exampe is meant to be run with the python example:
//              tornado_example.py 
//              from the course GitHub repository: tornado_bare, branch sklearn_example


// if you do not know your local sharing server name try:
//    ifconfig |grep inet   
// to see what your public facing IP address is, the ip address can be used here
let SERVER_URL = "http://192.168.0.11:8000" // change this for your server name!!!

import UIKit
import CoreML

//The protocol used in order to use a responsive Modal View for training different models
protocol ModalDelegate {
    func setParametersAndTrain(modelType: Int, withParameters parameters:[Int])
}

class ViewController: UIViewController, URLSessionDelegate, UIPickerViewDelegate,UIPickerViewDataSource,ModalDelegate {
    
    // MARK: Class Properties
    lazy var session: URLSession = {
        let sessionConfig = URLSessionConfiguration.ephemeral
        
        sessionConfig.timeoutIntervalForRequest = 5.0
        sessionConfig.timeoutIntervalForResource = 8.0
        sessionConfig.httpMaximumConnectionsPerHost = 1
        
        return URLSession(configuration: sessionConfig,
            delegate: self,
            delegateQueue:self.operationQueue)
    }()
    
    //AudioModel used to capture microphone data, with a buffer size appropriate for lower sampling rate phones
    let audio = AudioModel(buffer_size: 44100)
    
    lazy var dataModel = {return DataModel.sharedInstance()}()

    
    let operationQueue = OperationQueue()
    let motionOperationQueue = OperationQueue()
    let calibrationOperationQueue = OperationQueue()
    
    let animation = CATransition()
    
    //Labels to fill a picker wheel for model classification task
    var instrumentData = ["Piano", "Singing", "Guitar",
                          "Violin", "Cello", "Saxophone",
                          "Flute", "Clarinet", "Trumpet", "Drums"]
    
    
    //Pre-made model for piano sound classification, used only when appropriate boolean flag is set
    lazy var turiModel:PianoModel = {
        do{
            let config = MLModelConfiguration()
            return try PianoModel(configuration: config)
        }catch{
            print(error)
            fatalError("Could not load custom model")
        }
    }()
    
    //Local variables to store raw data and fft data for passing to model
    var fftData:[Float] = Array.init(repeating: 0.0, count: 44100/2)
    var timeData:[Float] = Array.init(repeating: 0.0, count: 44100)
    
    
    // MARK: ViewController Outlets
    @IBOutlet weak var instrumentPhoto: UIImageView!
    
    @IBOutlet weak var instrumentPicker: UIPickerView!
    
    @IBOutlet weak var testButton: UIButton!
    
    @IBOutlet weak var didRecord: UILabel!
    
    @IBOutlet weak var toggleCoreButton: UIButton!
    

    
    // MARK: Class Properties with Observers
    var dsid:Int = 100
    
    // convert to ML Multi array
    // https://github.com/akimach/GestureAI-CoreML-iOS/blob/master/GestureAI/GestureViewController.swift
    // adapted from link above to work for our dataset
    // It should use floats instead of doubles, but apparently floats aren't supported on the iOS versions we had access to
    private func toMLMultiArray(_ arr: [Double]) -> MLMultiArray {
        guard let sequence = try? MLMultiArray(shape:[22050], dataType:MLMultiArrayDataType.double) else {
            fatalError("Unexpected runtime error. MLMultiArray could not be created")
        }
        let size = Int(truncating: sequence.shape[0])
        for i in 0..<size {
            sequence[i] = NSNumber(floatLiteral: arr[i])
        }
        return sequence
    }
    
    // MARK: View Controller Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        
        // create reusable animation
        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
        animation.type = CATransitionType.fade
        animation.duration = 0.5
        
        didRecord.isHidden = true
        
        //set delegate things for picker wheel
        self.instrumentPicker.delegate = self
        self.instrumentPicker.dataSource = self
        instrumentPicker.selectRow(0, inComponent: 0, animated: true)
        
        
        dsid = 1 // set this and it will update UI
    }

    //MARK: Get New Dataset ID
    @IBAction func getDataSetId(_ sender: AnyObject) {
        // create a GET request for a new DSID from server
        let baseURL = "\(SERVER_URL)/GetNewDatasetId"
        
        let getUrl = URL(string: baseURL)
        let request: URLRequest = URLRequest(url: getUrl!)
        let dataTask : URLSessionDataTask = self.session.dataTask(with: request,
            completionHandler:{(data, response, error) in
                if(error != nil){
                    print("Response:\n%@",response!)
                }
                else{
                    let jsonDictionary = self.convertDataToDictionary(with: data)
                    
                    // This better be an integer
                    if let dsid = jsonDictionary["dsid"]{
                        self.dsid = dsid as! Int
                    }
                }
                
        })
        
        dataTask.resume() // start the task
        
    }
    
    //MARK: Calibration
    //Hijacked previous "calibration" function, this takes care of taking a sample of audio to train a model
    //Samples are 1 second in length and labeled as either Piano or Not Piano (binary classification)
    @IBAction func startCalibration(_ sender: AnyObject) {
        
        didRecord.text = "Listening."
        didRecord.isHidden = false
        audio.startMicrophoneProcessing(withFps: 10)
        audio.play()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1000), execute: {
            self.fftData = self.audio.fftData
            self.timeData = self.audio.timeData
            
            self.audio.endAudioProcessing()
            
            self.sendFeatures(self.fftData,withLabel: self.instrumentPicker.selectedRow(inComponent: 0))
            
            self.didRecord.text = "Recorded!"
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(800)) {
                self.didRecord.isHidden = true
            }
            
        })
        
    }
    
    //MARK: Comm with Server
    //send data to server to store and use for model training
    func sendFeatures(_ array:[Float], withLabel label:Int){
        let baseURL = "\(SERVER_URL)/AddDataPoint"
        let postUrl = URL(string: "\(baseURL)")
        
        // create a custom HTTP POST request
        var request = URLRequest(url: postUrl!)
        
        // data to send in body of post request (send arguments as json)
        
        
        let jsonUpload:NSDictionary = ["feature":array,
                                       "label":"\(label)",
                                       "dsid":self.dsid]
        
        
        let requestBody:Data? = self.convertDictionaryToData(with:jsonUpload)
        
        request.httpMethod = "POST"
        request.httpBody = requestBody
        
        let postTask : URLSessionDataTask = self.session.dataTask(with: request,
            completionHandler:{(data, response, error) in
                if(error != nil){
                    if let res = response{
                        print("Response:\n",res)
                    }
                }
                else{
                    let jsonDictionary = self.convertDataToDictionary(with: data)
                    
                    print(jsonDictionary["feature"]!)
                    print(jsonDictionary["label"]!)
                }

        })
        
        postTask.resume() // start the task
    }
    
    //MARK: Comm with Server to query ML Model
    func getPrediction(_ array:[Float]){
        let baseURL = "\(SERVER_URL)/PredictOne"
        let postUrl = URL(string: "\(baseURL)")
        
        // create a custom HTTP POST request
        var request = URLRequest(url: postUrl!)
        
        // data to send in body of post request (send arguments as json)
        let jsonUpload:NSDictionary = ["feature":array, "dsid":self.dsid]
        
        
        let requestBody:Data? = self.convertDictionaryToData(with:jsonUpload)
        
        request.httpMethod = "POST"
        request.httpBody = requestBody
        
        let postTask : URLSessionDataTask = self.session.dataTask(with: request,
                                                                  completionHandler:{
                        (data, response, error) in
                        if(error != nil){
                            if let res = response{
                                print("Response:\n",res)
                            }
                        }
                        else{ // no error we are aware of
                            let jsonDictionary = self.convertDataToDictionary(with: data)
                            
                            let labelResponse = jsonDictionary["prediction"]!
                                                                                    
                            self.displayLabelResponse(labelResponse as! String)

                        }
                                                                    
        })
        
        postTask.resume() // start the task
    }
    //Display response from model query
    func displayLabelResponse(_ response:String){
        
        DispatchQueue.main.async {
            switch response {
            case "['0']":
                self.didRecord.text = "Not Piano"
            case "['1']":
                self.didRecord.text = "Piano"
            default:
                self.didRecord.text = "Unsure"
            }
            
            self.didRecord.isHidden = false
        }
        
    }
    
    //Button action to segue to model creation Modal View
    @IBAction func makeModel(_ sender: AnyObject) {
        let modalController = storyboard?.instantiateViewController(withIdentifier: "ModalViewController") as! ModalViewController
        modalController.delegate = self
        self.present(modalController, animated: true, completion: nil)
        
    }
    
    //Protocol function that's run after modal view is returned from, takes parameters from modal view to train appropriate model
    func setParametersAndTrain(modelType: Int, withParameters parameters:[Int]) {
        // create a GET request for server to update the ML model with current data
        let baseURL = "\(SERVER_URL)/UpdateModel"
    
        var query = "?dsid=\(self.dsid)&modelType=\(modelType)"
        
        //add correct parameters to query
        for index in 0..<parameters.count{
            query += "&param\(index)=\(parameters[index])"
        }
        
        let getUrl = URL(string: baseURL+query)
        let request: URLRequest = URLRequest(url: getUrl!)
        let dataTask : URLSessionDataTask = self.session.dataTask(with: request,
              completionHandler:{(data, response, error) in
                // handle error!
                if (error != nil) {
                    if let res = response{
                        print("Response:\n",res)
                    }
                }
                else{
                    let jsonDictionary = self.convertDataToDictionary(with: data)
                    
                    if let resubAcc = jsonDictionary["resubAccuracy"]{
                        print("Resubstitution Accuracy is", resubAcc)
                    }
                    
                    let bestModel = jsonDictionary["best_model"]!
                    
                    if(bestModel as! String != "unknown"){
                        
                        DispatchQueue.main.async {
                            self.didRecord.text = (bestModel as! String)
                            
                            self.didRecord.isHidden = false
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1000), execute: {
                            self.didRecord.isHidden = true
                        })
                    
                        
                    }
                }
                                                                    
        })

        dataTask.resume() // start the task
    }
    
    //Button to Query Model for a prediction. Takes 1 second of audio and applies model for binary classification
    @IBAction func testAudio(_ sender: Any) {
        
        didRecord.text = "Listening."
        didRecord.isHidden = false
        audio.startMicrophoneProcessing(withFps: 10)
        audio.play()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1000), execute: {
            self.fftData = self.audio.fftData
            self.timeData = self.audio.timeData
            
            self.audio.endAudioProcessing()
            
            self.didRecord.text = "Recorded!"
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(800)) {
                
                if(self.coreMLFlag){
                    //predict a label
                    let doubleArray:[Double] = self.fftData.map{Double($0)}
                    let seq = self.toMLMultiArray(doubleArray)
                
                    
                    guard let outputTuri = try? self.turiModel.prediction(sequence: seq) else {
                        
                        fatalError("Unexpected runtime error.")
                    }
                    let tempOutput = "['" + outputTuri.target + "']"
                    self.displayLabelResponse(tempOutput)
                }else{
                    self.getPrediction(self.fftData)
                }
            }
            
        })
        
    }
    
    
    //MARK: JSON Conversion Functions
    func convertDictionaryToData(with jsonUpload:NSDictionary) -> Data?{
        do { // try to make JSON and deal with errors using do/catch block
            let requestBody = try JSONSerialization.data(withJSONObject: jsonUpload, options:JSONSerialization.WritingOptions.prettyPrinted)
            return requestBody
        } catch {
            print("json error: \(error.localizedDescription)")
            return nil
        }
    }
    
    func convertDataToDictionary(with data:Data?)->NSDictionary{
        do { // try to parse JSON and deal with errors using do/catch block
            let jsonDictionary: NSDictionary =
                try JSONSerialization.jsonObject(with: data!,
                                              options: JSONSerialization.ReadingOptions.mutableContainers) as! NSDictionary
            
            return jsonDictionary
            
        } catch {
            
            if let strData = String(data:data!, encoding:String.Encoding(rawValue: String.Encoding.utf8.rawValue)){
                            print("printing JSON received as string: "+strData)
            }else{
                print("json error: \(error.localizedDescription)")
            }
            return NSDictionary() // just return empty
        }
    }
    
    
    //Button action to create a new CoreML exported model
    //For use by engineers, should remove in "Final Release"
    @IBAction func exportModel(_ sender: Any) {
        
        // create a GET request for server to update the ML model with current data
        let baseURL = "\(SERVER_URL)/ExportModel"
        let query = "?dsid=\(self.dsid)"
        let getUrl = URL(string: baseURL+query)
        let request: URLRequest = URLRequest(url: getUrl!)
        let dataTask : URLSessionDataTask = self.session.dataTask(with: request,
              completionHandler:{(data, response, error) in
                // handle error!
                if (error != nil) {
                    if let res = response{
                        print("Response:\n",res)
                    }
                }
                else{
                    let jsonDictionary = self.convertDataToDictionary(with: data)
                    print("Model Exported")
                }
                                                                    
        })

        dataTask.resume() // start the task
        
        
    }
    
    //Button action to change whether you want to use CoreML local model or server model for classification
    var coreMLFlag = false
    @IBAction func toggleCoreML(_ sender: Any) {
        
        coreMLFlag.toggle()
        if(coreMLFlag){
            self.toggleCoreButton.setTitle("Using CoreML", for:.normal)
        }else{
            self.toggleCoreButton.setTitle("Not Using CoreML", for:.normal)
        }
    }
    
    //MARK: Maitenance functions for Picker Wheel
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
            return 1
    }
        
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return instrumentData.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        print(instrumentData[row])
        return instrumentData[row]
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if let name = instrumentData[row] as? String {
            //instrumentPhoto?.image? = self.dataModel.getImageWithName(name)
        }
    }
    
    

    
    
}





