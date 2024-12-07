## no bully my ugly code - pio

from utility import *

import threading
import json
import requests
from pyperclip import copy as setClipboard

Patterns = [
    b'\x73\x70\x6C\x6F\x69\x74\x49\x6E\x69\x74', # Inject Script
    b'\x74\x73\x70\x6C\x6F\x69\x74\x4C\x6F\x61\x64\x00\x00\x00\x00', # roblox listener
]

class Bridge:
    def __init__(self):
        self.sendSession = 0
        self.address = 0

    def Scan(self, pattern):
        for aob in AOBScanAll(pattern):
            if readBytes(aob - 0x50, 2) == b'\x00\x00':
                self.address = aob
        
        if self.address != 0:
            psuccess(f"Got bridge sender: {hex(self.address)}")

            loadCache = open("visionLoad.cache", "w")
            loadCache.write(str(self.address))
            loadCache.close()

        else:
            self.Scan(pattern)

    def Send(self, string):
        if self.address == 0:
            self.address = self.Get()
            
        self.sendSession += 1
        newBytes = f"--[[{self.sendSession}]] {string}\0"
        writeBytes(self.address, bytes(newBytes, encoding = 'utf-8'), len(newBytes))

    def Get(self):
        loadCache = open("visionLoad.cache", "r")
        loadAddy = loadCache.read()
        loadCache.close()

        return int(loadAddy)

    def OnReceive(self, receiver_object, callback):
        def Loop():
            Value = receiver_object.Value
            while True:
                if not isOpened():
                    break

                newValue = receiver_object.Value
                if newValue != Value:
                    callback(newValue)
                    Value = newValue

        self.receiverThread = threading.Thread(target=Loop, daemon=True)
        self.receiverThread.start()

class API:
    def __init__(self):
        self.newBridge = Bridge()
        self.Injecting = False

    def scanInject(self):
        newScript = 0

        for aob in AOBScanAll(Patterns[0]):
            if newScript != 0:
                break

            if aob:
                intBytes = intToBytes(aob)
                newPattern = bytesToPattern(intBytes)

                pinfo(f"Scanning on '{newPattern.decode('utf-8')[2:]}'".replace("\\x", " "))

                for aob2 in AOBScanAll(newPattern):
                    free()
                    
                    if aob2 and readQword(aob2 - offsets["Name"] + 8) == aob2 - offsets["Name"]:
                        newScript = toInstance(aob2 - offsets["Name"])
                        break

        return newScript
    
    @property
    def Injected(self):
        try:
            roblox = openProcess("RobloxPlayerBeta.exe")

            if not roblox:
                openProcess("Windows10Universal.exe")
            
            identifier = readString(self.newBridge.Get())
            return (identifier.startswith("--[[") or identifier.startswith("tsp")) or False
        except:
            return False
        
    @property
    def Receiver(self):
        if self.Injected:
            self.clientReplicator = getClientReplicator()
            self.dataModel = self.clientReplicator.GetLastAncestor()
            return self.dataModel.FindFirstChild("BridgeService").FindFirstClass("StringValue")
        
    def Inject(self):
        if self.Injecting:
            return
        
        if self.Injected:
            messageBox("Vision", "Already injected.")
            return
        
        if not isOpened():
            messageBox("Vision", "No roblox process found.")
            return
        
        self.Injecting = True
        
        #pause()
        free()
        
        self.clientReplicator = getClientReplicator()
        self.dataModel = self.clientReplicator.GetLastAncestor()

        while not self.dataModel.FindFirstChild("BridgeService"):
            pass

        # self.targetScript.Bytecode = oldScriptBytecode
        print("got bridge service")
        self.newBridge.Scan(Patterns[1])

        self.bridgeServiceScript = self.dataModel.FindFirstChild("BridgeService")
        self.receiverInstance = self.bridgeServiceScript.FindFirstClass("StringValue")
        
        pinfo(self.receiverInstance.Value)
        self.newBridge.OnReceive(self.receiverInstance, self.onReceiveCB)

        self.newBridge.Send("[connected] true")

        self.Injecting = False

        def executeFolder(folder):
            for script in listdir(folder):
                if path.isdir(folder + "/" + script):
                    executeFolder(folder + "/" + script)
                else:
                    self.Execute(open(folder + "/" + script, "r").read())
        executeFolder(os.getcwd() + "/autoexecute")


    def Execute(self, string):
        if self.Injected:
            self.newBridge.Send(string)
        else:
            messageBox("Vision", "Please inject first.")
    
    def onReceiveCB(self, a):
        if a:
            jsonOutput = json.loads(a)

            for k, v in jsonOutput.items():
                if k == "session":
                    continue
                
                pinfo(f"got request of {k} with value {v}")

                if k == "httpGet":
                    httpResponse = requests.get(v).content
                    httpResponse = httpResponse.decode('utf-8') or "invalid"
                    self.newBridge.Send(f"[{k}] {httpResponse}")
                elif k == "setClipboard":
                    setClipboard(v)
                elif k == "bbc":
                    system("start https://i.pinimg.com/736x/54/bc/af/54bcafd0a6155d5c7f4d626f533c0411.jpg")

                elif k == "freeBOBUXTROLL":
                    system("start https://www.yout-ube.com/watch?v=dQw4w9WgXcQ")

                elif k == "readFile":
                    fileResponse = getfile(v, "r")
                    fileContent = "File does not exist!"

                    if fileResponse != "File does not exist!":
                        fileContent = fileResponse.read()
                        fileResponse.close()

                    self.newBridge.Send(f"[{k}] {fileContent}")

                elif k == "writeFile":
                    fileResponse = getfile(v[0], "w")
                    
                    if fileResponse != "File does not exist!":
                        fileResponse.write(v[1])
                        fileResponse.close()

                elif k == "appendfile":
                    fileResponse = getfile(v[0], "a")
                    
                    if fileResponse != "File does not exist!":
                        fileResponse.write(v[1])
                        fileResponse.close()

                elif k == "isFile":
                    filePath = getcorrectpath(v)

                    self.newBridge.Send(f"[{k}] {str(path.isfile(filePath))}")

                elif k == "delFile":
                    filePath = getcorrectpath(v)
                    if path.isfile(filePath):
                        remove(filePath)

                elif k == "listFiles":
                    dirPath = getcorrectpath(v)

                    filesList = []

                    if path.isdir(dirPath):
                        filesList = listdir(dirPath)

                    self.newBridge.Send(f"[{k}] {json.dumps(filesList)}")

                elif k == "isFolder":
                    dirPath = getcorrectpath(v)

                    self.newBridge.Send(f"[{k}] {str(path.isdir(dirPath))}")

                elif k == "makeFolder":
                    dirPath = getcorrectpath(v)
                    filePath = getcorrectpath(v)
                    if path.isfile(filePath):
                        remove(filePath)

                elif k == "listFiles":
                    dirPath = getcorrectpath(v)

                    filesList = []

                    if path.isdir(dirPath):
                        filesList = listdir(dirPath)

                    self.newBridge.Send(f"[{k}] {json.dumps(filesList)}")

                elif k == "isFolder":
                    dirPath = getcorrectpath(v)

                    self.newBridge.Send(f"[{k}] {str(path.isdir(dirPath))}")

                elif k == "makeFolder":
                    dirPath = getcorrectpath(v)

                    try:
                        mkdir(dirPath)
                    except:
                        pass

                elif k == "delFolder":
                    dirPath = getcorrectpath(v)

                    if path.isdir(dirPath):
                        rmdir(dirPath)

    def Connect(self):
        if self.Injected:
            self.newBridge.OnReceive(self.Receiver, self.onReceiveCB)
