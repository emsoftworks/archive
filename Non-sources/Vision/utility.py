import pymem
import ctypes
import time
import glob
import re

from sty import fg, Style, RgbFg
from os import path, system, kill, getcwd, remove, listdir, mkdir, rmdir
from signal import SIGTERM

# foeking crash fixed the problem was too many modules if i only used 1 custom module it wont crash idk why is that

system("color") # Make colors work in command prompt

user32 = ctypes.windll.user32
kernel32 = ctypes.WinDLL("kernel32.dll")

currentProcess = None
psutilProcess = None

fg.visionColor = Style(RgbFg(156, 81, 252))

wait = time.sleep

offsets = {
    "Name": 0x48,
    "ClassName": 0x18,
    "Parent": 0x60,
    "Children": 0x50,
    "Primitive": 0x148,
    "Character": 0x188,

    "ElCapor": {
        "ClassDescriptor": 0x18,
        "PropertyDescriptor": 0x28,

        "ReturnType": 0x24,

        "GetSet": 0x30,
        "Get": 0x8,
        "Set": 0x18
    }
}

logsPaths = {
    "RobloxPlayerBeta.exe": path.expandvars(r'%LOCALAPPDATA%\Roblox\logs'),
    "Windows10Universal.exe": path.expandvars(r'%LOCALAPPDATA%\Packages\ROBLOXCORPORATION.ROBLOX_55nm5eh3cm0pr\LocalState\logs')
}

def getcorrectpath(filepath):
    current_directory = getcwd()
    file_name = "workspace\\" + filepath
    file_name = file_name.replace("/", "\\")
    file_path = path.join(current_directory, file_name)

    if path.abspath(file_path).startswith(path.abspath(current_directory)):
        print(path.abspath(current_directory), path.abspath(file_path))
        return file_path
    else:
        root = path.abspath(file_path).split(file_name)[0]
        return file_name.replace(root, "")[1:]

def getfile(filepath, mode):
    current_directory = getcwd()
    file_name = "workspace\\" + filepath
    file_name = file_name.replace("/", "\\")
    file_path = path.join(current_directory, file_name)

    if path.abspath(file_path).startswith(path.abspath(current_directory)):
        try:
            return open(file_path, mode)
        except:
            return "File does not exist!"
    else:
        root = path.abspath(file_path).split(file_name)[0]
        try:
            return open(file_name.replace(root, "")[1:], mode)
        except:
            return "File does not exist!"

def messageBox(title, text):
    return user32.MessageBoxW(0, text, title, 0x00001000)

 # there you go nibba jalon

def pinfo(*kargs, custom = "!"):
    #print(f"\t[{fg.visionColor}{custom}{fg.rs}]", *kargs)
    pass

def psuccess(*kargs):
    #print(f"\t[{fg(76)}+{fg.rs}]", *kargs)
    pass

def perror(*kargs):
    #print(f"\t[{fg(160)}-{fg.rs}]", *kargs)
    pass

def getLatestFile(folder_path, extension, name_contains):
    search_pattern = path.join(
        folder_path, f"*{name_contains}*.{extension}"
    )

    files = glob.glob(search_pattern)

    if not files:
        return None

    latest_file = max(files, key=path.getctime)

    return latest_file

def getClientReplicator():
    logsFile = open(getLatestFile(logsPaths[currentProcess.process_base.name], "log", "Player"), 'r')

    replicatorAddress = 0
    addressResults = re.findall("Replicator created: (\\w+)", logsFile.read())
    
    if len(addressResults) > 0:
        replicatorAddress = int(addressResults[-1], 16)

    logsFile.close()

    return toInstance(replicatorAddress)

def intToBytes(val):
    t = [ val & 0xFF ]
    for i in range(1, 8):
        t.append((val >> (8 * i)) & 0xFF)
    
    return t

def bytesToPattern(val):
    newpattern = ""
    for byte in val:
        newpattern = newpattern + '\\x' + format(byte, "02X")
    
    return bytes(newpattern, encoding="utf-8")

# CE ENVS

def openProcess(name):
    global currentProcess
    
    try:
        currentProcess = pymem.Pymem(name)

        return currentProcess
    except:
        return False
    
def isOpened():
    try:
        return currentProcess.process_base
    except:
        return False
    
def kms():
    kill(currentProcess.process_id, SIGTERM)

def free():
    currentProcess.free(currentProcess.base_address)

def pause():
    kernel32.DebugActiveProcess(currentProcess.process_id)

def resume():
    kernel32.DebugActiveProcessStop(currentProcess.process_id)

def AOBScan(pattern):
    try:
        return pymem.pattern.pattern_scan_all(currentProcess.process_handle, pattern, return_multiple=False)
    except:
        return False

def AOBScanAll(pattern):
    try:
        return pymem.pattern.pattern_scan_all(currentProcess.process_handle, pattern, return_multiple=True)
    except:
        return []

def allocateMemory(size):
    try:
        return pymem.memory.allocate_memory(currentProcess.process_handle, size)
    except:
        return False
    
def searchString(string):
    newpattern = ""

    for c in string:
        newpattern = newpattern + "\\x" + format(ord(c), "02X")

    return AOBScan(bytes(newpattern, "utf-8"))
    
## READ FUNCTIONS

def readBytes(address, bytecount, returnastable = False):
    try:
        result = currentProcess.read_bytes(address, bytecount)

        if not returnastable:
            return result
        elif returnastable:
            return list(result)
    except:
        return False
    
def readInteger(address):
    try:
        return currentProcess.read_int(address)
    except:
        return False
    
def readBool(address):
    try:
        return currentProcess.read_bool(address)
    except Exception as e:
        return False

def readQword(address):
    try:
        return currentProcess.read_longlong(address)
    except:
        return False
    
def readFloat(address):
    try:
        return currentProcess.read_float(address)
    except:
        return False
    
def readDouble(address):
    try:
        return currentProcess.read_double(address)
    except:
        return False
    
def readString(address, byte = 100):
    try:
        return currentProcess.read_string(address, byte)
    except Exception as e:
        return False
    
def readChar(address):
    try:
        return currentProcess.read_char(address)
    except:
        return False
    
## WRITE FUNCTIONS

def writeBytes(address, value, bytecount):
    #try:
    return currentProcess.write_bytes(address, value, bytecount)
    #except:
        #return False
    
def writeInteger(address, value):
    try:
        return currentProcess.write_int(address, value)
    except:
        return False
    
def writeBool(address, value):
    try:
        return currentProcess.write_bool(address, value)
    except:
        return False

def writeQword(address, value):
    try:
        return currentProcess.write_longlong(address, value)
    except:
        return False
    
def writeFloat(address, value):
    try:
        return currentProcess.write_float(address, value)
    except:
        return False
    
def writeDouble(address, value):
    try:
        return currentProcess.read_double(address, value)
    except:
        return False
    
def writeString(address, value):
    try:
        return currentProcess.write_string(address, value)
    except:
        return False

## EXPLOIT CLASSES

class getSetImpl:
    def __init__(self, address):
        self.address = address

    def Get(self):
        return readQword(self.address + offsets["ElCapor"]["Get"])
    
    def Set(self):
        return readQword(self.address + offsets["ElCapor"]["Set"])
    
class propertyDescriptor:
    def __init__(self, address):
        self.address = address

    @property
    def Name(self):
        return readString(readQword(self.address + 0x8))
    
    @property
    def ReturnType(self):
        return readString(DRP(self.address + offsets["ElCapor"]["ReturnType"]))

    def GetSecurity(self):
        return readInteger(self.address + 0x1C)
    
    def SetSecurity(self, new_security):
        writeInteger(self.address + 0x1C, new_security)

    def GetSet(self):
        return getSetImpl(readQword(self.address + offsets["ElCapor"]["GetSet"]))

def DRP(Address:int) -> int:
    Address = Address
    if type(Address) == str:
        Address = int(Address, 16)
    return int.from_bytes(readBytes(Address, 8),'little')
def ReadStringUntilEnd(self, Address:int) -> str:
    if type(Address) == str:
        Address = int(Address, 16)
    if Address == 0:
        return ""
    CurrentAddress = Address
    StringData = []
    LoopedTimes = 0
    while LoopedTimes < 15000:
        if Program.read_bytes(CurrentAddress,1) == b'\x00':
            break
        StringData.append(Program.read_bytes(CurrentAddress,1))
        CurrentAddress += 1
        LoopedTimes += 1
    String = bytes()
    for i in StringData:
        String = String + i
    return str(String)[2:-1]
def ReadInstaceString(Address:int) -> str:
    try:
        length = readInteger(readQword(Address) + 0x10)
        if (length < 16 and length > 0):
            return ReadStringUntilEnd(readQword(Address))
        else:
            return ReadStringUntilEnd(readQword(readQword(Address)))
    except:
        return ""
def ReadNormalString(Address:int) -> str:
    length = readInteger(Address + 0x10)
    if (length < 16 and length > 0):
        return ReadStringUntilEnd(Address)
    else:
        return ReadStringUntilEnd(readQword(Address))
		

class toInstance:
    def __init__(self, address):
        self.address = address
    
    @property
    def Name(self):
        Pointer = readQword(self.address + offsets["Name"])

        if Pointer:
            QWord = readQword(Pointer + 0x18)

            if QWord == 0x1F:
                Pointer = readQword(Pointer)
            
            if readString(readQword(Pointer)):
                return readString(readQword(Pointer))
            else:
                return readString(Pointer)
        
        return "???"
    
    @property
    def ClassName(self):
        Pointer = readQword(self.address + offsets["ClassName"])
        Pointer = readQword(Pointer + 0x8)

        if Pointer:
            QWord = readQword(Pointer + 0x18)

            if QWord == 0x1F:
                Pointer = readQword(Pointer)
            
            if readString(readQword(Pointer)):
                return readString(readQword(Pointer))
            else:
                return readString(Pointer)
        
        return "???"
    
    @property
    def Parent(self):
        return toInstance(readQword(self.address + offsets["Parent"]))
    
    @property
    def LocalPlayer(self):
        if self.ClassName == "Players":
            return self.GetChildren()[0]
        
    @property
    def Bytecode(self):
        if self.ClassName == "LocalScript" or self.ClassName == "ModuleScript" or self.ClassName == "Script" or self.ClassName == "CoreScript":
            return readBytes(self.address + 0x100, 0x150)
        
    @property
    def Value(self):
        if self.ClassName == "StringValue":
            Addy = self.address + 0xC0
            Pointer = readQword(Addy)
            
            if readString(Pointer):
                return readString(Pointer, 1000) # 1000 is the length of the string to be read
            elif readString(Addy):
                return readString(Addy, 1000)
        elif self.ClassName == "ObjectValue":
            return toInstance(readQword(self.address + 0xC0))
            
    @property
    def Character(self):
        if self.ClassName == "Player":
            return toInstance(readQword(self.address + offsets["Character"]))
            
    @property
    def Position(self):
        if self.ClassName.endswith("Part"):
            Pointer = readQword(self.address + offsets["Primitive"])
            Pointer = readQword(Pointer + 0x98)

            X, Y, Z = 0, 0, 0

            if Pointer:
                X = readFloat(Pointer + 0x6C)
                Y = readFloat(Pointer + 0x70)
                Z = readFloat(Pointer + 0x74)

            return [X, Y, Z]

    @property
    def ClassDescriptor(self):
        Descriptor = readQword(self.address + 0x18)

        return propertyDescriptor(Descriptor)
    
    def GetPropertyDescriptors(self):
        begin = readQword(self.ClassDescriptor.address + offsets["ElCapor"]["PropertyDescriptor"])
        end = readQword(self.ClassDescriptor.address + offsets["ElCapor"]["PropertyDescriptor"] + 0x8)

        properties = []

        for current in range(begin, end + 1, 8):
            current_property = readQword(current)
            currentDescriptor = propertyDescriptor(current_property)
            if currentDescriptor.Name:
                properties.append(currentDescriptor)

        return properties

    def GetPropertyDescriptor(self, name):
        descriptor = None

        for desc in self.GetPropertyDescriptors():
            if name == desc.Name:
                descriptor = desc
                break

        return descriptor

    def GetProperty(self, name):
        #     		ReturnType = roblox.ReadInstaceString(roblox.DRP(propertyDescriptor.GetAddress() + property_descriptor_offsets["returntype"])+0x4)
		# if ReturnType in getPropertyFuncs:
		# 	getfunc = getPropertyFuncs[ReturnType]
		# 	if name == "Character":
		# 		FunctionAddress = roblox.DRP(roblox.DRP(self.GetPropertyDescriptor(name).GetAddress() + 0x34) + 0x8)
		# 		getfunc.write(self.addr, FunctionAddress)
		# 	else:
		# 		getfunc.write(self.addr, propertyDescriptor.GetSet().Get())
		# 	return getfunc.call()
		# else:
		# 	return ReturnType + " Not Implemented"

        descriptor = self.GetPropertyDescriptor(name)
        return descriptor
    def GetChildren(self):
        Instances = []
        
        Pointer = readQword(self.address + offsets["Children"])

        if Pointer:
            Top = readQword(Pointer)
            End = readQword(Pointer + 8)

            Current = Top

            for Current in range(Top, End + 1, 16):
                ChildInstance = readQword(Current)
                
                Instances.append(toInstance(ChildInstance))
        
        return Instances
    
    def FindFirstChild(self, name, scandescendant=False):
        selection = None

        if not scandescendant:
            selection = self.GetChildren()
        else:
            selection = self.GetDescendants()

        for Child in selection:
            if Child.Name == name:
                return Child
            
    def FindFirstClass(self, name, scandescendant=False):
        selection = None

        if not scandescendant:
            selection = self.GetChildren()
        else:
            selection = self.GetDescendants()

        for Child in selection:
            if Child.ClassName == name:
                return Child
            
    def GetTools(self):
        if self.ClassName == "Backpack":
            Tools = []

            for Children in self.GetChildren():
                if Children.ClassName == "Tool":
                    Tools.append(Children)

            return Tools
    
    def GetDescendants(self):
            Descendant = []

            def Scan(Object):
                for Child in Object.GetChildren():
                    Descendant.append(Child)
                    Scan(Child)

            Scan(self)

            return Descendant
            
    def GetLastAncestor(self):
        Ancestors = []

        def GetAncestor(Object):
            if Object.Parent.Name != "???":
                GetAncestor(Object.Parent)
                Ancestors.append(Object.Parent)
        
        GetAncestor(self.Parent)

        return Ancestors[-1]
        
    def __setattr__(self, name, value):
        if name == "Name":
            Pointer = readQword(self.address + offsets["Name"])

            if Pointer:
                QWord = readQword(Pointer + 0x18)

                if QWord == 0x1F:
                    Pointer = readQword(Pointer)
                
                if readString(readQword(Pointer)):
                    writeString(readQword(Pointer), value)
                else:
                    writeString(Pointer, value)

        elif name == "ClassName": # funny if u set PlayerGui classname to CoreGui
            Pointer = readQword(self.address + offsets["ClassName"])
            Pointer = readQword(Pointer + 0x8)
            
            if Pointer:
                QWord = readQword(Pointer + 0x18)

                if QWord == 0x1F:
                    Pointer = readQword(Pointer)
                
                if readString(readQword(Pointer)):
                    writeString(readQword(Pointer), value)
                else:
                    writeString(Pointer, value)

        elif name == "Bytecode":
            writeBytes(self.address + 0x100, value, 0x150)

        elif name == "Parent": # still dont have a fully working set parent the current one just spoofs it
            pass
        
        else:
            self.__dict__[name] = value