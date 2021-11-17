#!/usr/bin/python

from pymongo import MongoClient
import tornado.web
from sklearn.neighbors import KNeighborsClassifier

from tornado.web import HTTPError
from tornado.httpserver import HTTPServer
from tornado.ioloop import IOLoop
from tornado.options import define, options

from basehandler import BaseHandler

import turicreate as tc
import pickle
from bson.binary import Binary
import json
import numpy as np

class PrintHandlers(BaseHandler):
    def get(self):
        '''Write out to screen the handlers used
        This is a nice debugging example!
        '''
        self.set_header("Content-Type", "application/json")
        self.write(self.application.handlers_string.replace('),','),\n'))

class UploadLabeledDatapointHandler(BaseHandler):
    def post(self):
        '''Save data point and class label to database
        '''
        data = json.loads(self.request.body.decode("utf-8"))

        vals = data['feature']
        fvals = [float(val) for val in vals]
        label = data['label']
        sess  = data['dsid']

        dbid = self.db.labeledinstances.insert(
            {"feature":fvals,"label":label,"dsid":sess}
            );
        self.write_json({"id":str(dbid),
            "feature":[str(len(fvals))+" Points Received",
                    "min of: " +str(min(fvals)),
                    "max of: " +str(max(fvals))],
            "label":label})

class RequestNewDatasetId(BaseHandler):
    def get(self):
        '''Get a new dataset ID for building a new dataset
        '''
        a = self.db.labeledinstances.find_one(sort=[("dsid", -1)])
        if a == None:
            newSessionId = 1
        else:
            newSessionId = float(a['dsid'])+1
        self.write_json({"dsid":newSessionId})

class UpdateModelForDatasetId(BaseHandler):
    def get(self):
        '''Train a new model (or update) for given dataset ID
        '''
        dsid = self.get_int_arg("dsid",default=0)

        data = self.get_features_and_labels_as_SFrame(dsid)

        #Parameter containing model type to use (as an Int)
        modelType = int(self.get_argument("modelType",default = ""))

        #Parameters for model training, if not doing comparison only one of these is set
        modelParam0 = int(self.get_argument("param0", default = 1))
        modelParam1 = int(self.get_argument("param1", default = 1))
        

        # fit the model to the data
        acc = -1
        best_model = 'unknown'
        if len(data)>0:
            
            #Train an SVM model
            if modelType == 0:
                model = tc.svm_classifier.create(data,target='target',penalty = modelParam0,verbose = 0)
                yhat = model.predict(data)
                self.clf[dsid] = model
                acc = sum(yhat==data['target'])/float(len(data))
                # save model for use later, if desired
                model.save('../models/turi_model_dsid%d'%(dsid))

            #Train a scikit learn KNN model
            elif modelType == 1 :
                
                f = []
                l = []

                for x in self.db.labeledinstances.find({"dsid": dsid}):
                    l.append(x['label'])
                    f.append([float(val)for val in x['feature']])

        
                model = KNeighborsClassifier(n_neighbors = modelParam0)
                model.fit(f,l)
                yhat = model.predict(f)
                self.clf[dsid] = model
                acc = sum(yhat==l)/float(len(l))
                # save model for use later, if desired
                #model.save('../models/turi_model_dsid%d'%(dsid))

                bytes = pickle.dump(model)
                self.db.models.update({'dsid' : dsid},{'$set' : {'model' : Binary(bytes)}},upsert = True)

            #Train SVM and KNN to compare them
            elif modelType == 2:

                
                f = []
                l = []

                for x in self.db.labeledinstances.find({"dsid": dsid}):
                    l.append(x['label'])
                    f.append([float(val)for val in x['feature']])

                model_1 = tc.svm_classifier.create(data,target='target',penalty = modelParam1,verbose = 0)
                yhat_1 = model_1.predict(data)
                #self.clf[dsid] = model
                acc_1 = sum(yhat_1==data['target'])/float(len(data))
                # save model for use later, if desired
                #model.save('../models/turi_model_dsid%d'%(dsid))

        
                model_2 = KNeighborsClassifier(n_neighbors = modelParam0)
                model_2.fit(f,l)
                yhat_2 = model_2.predict(f)
                #self.clf[dsid] = model
                acc_2 = sum(yhat_2==l)/float(len(l))

                if acc_1 >= acc_2:
                    acc = acc_1
                    self.clf[dsid] = model_1
                    model_1.save('../models/turi_model_dsid%d'%(dsid))
                    best_model = 'SVM'
                else:
                    acc = acc_2
                    self.clf[dsid] = model_2
                    bytes = pickle.dump(model_2)
                    self.db.models.update({'dsid' : dsid},{'$set' : {'model' : Binary(bytes)}},upsert = True)
                    best_model = 'KNN'

            #Default, run turicreate classifier to test a ton of model types
            else:

                model = tc.classifier.create(data,target='target',verbose=0)# training
                yhat = model.predict(data)
                self.clf[dsid] = model
                acc = sum(yhat==data['target'])/float(len(data))
                # save model for use later, if desired
                model.save('../models/turi_model_dsid%d'%(dsid))

            
            
            

        # send back the resubstitution accuracy
        # if training takes a while, we are blocking tornado!! No!!
        self.write_json({"resubAccuracy":acc,
                            "best_model":best_model})

    def get_features_and_labels_as_SFrame(self, dsid):
        # create feature vectors from database
        features=[]
        labels=[]
        for a in self.db.labeledinstances.find({"dsid":dsid}): 
            features.append([float(val) for val in a['feature']])
            labels.append(a['label'])

        # convert to dictionary for tc
        data = {'target':labels, 'sequence':np.array(features)}

        # send back the SFrame of the data
        return tc.SFrame(data=data)

class PredictOneFromDatasetId(BaseHandler):
    def post(self):
        '''Predict the class of a sent feature vector
        '''
        data = json.loads(self.request.body.decode("utf-8"))    
        fvals = self.get_features_as_SFrame(data['feature'])
        dsid  = data['dsid']

        # load the model from the database (using pickle)
        # we are blocking tornado!! no!!
        if(self.clf == {} or not dsid in self.clf):
            print('Loading Model From file')
            try:
                self.clf[dsid] =  tc.load_model('../models/turi_model_dsid%d'%(dsid))
            except:
               print("Model file for DSID not found.") 
        
  
        if(dsid in self.clf):
            predLabel = self.clf[dsid].predict(fvals)
            self.write_json({"prediction":str(predLabel)})
        else:
            self.write_json({"prediction": "None"})
            

    def get_features_as_SFrame(self, vals):
        # create feature vectors from array input
        # convert to dictionary of arrays for tc

        tmp = [float(val) for val in vals]
        tmp = np.array(tmp)
        tmp = tmp.reshape((1,-1))
        data = {'sequence':tmp}

        # send back the SFrame of the data
        return tc.SFrame(data=data)

#Class to handle exporting a coreML model from a backend end-point
class ExportModel(BaseHandler) :
    def get(self):

        dsid = self.get_int_arg("dsid",default=0)

        try:
            self.clf[dsid].export_coreml("PianoModel.mlmodel")

        except:
            self.write_json({"Status": "Failed"})

        self.write_json({"Status": "Success"})


