import webview
from vision import API

VisionAPI = API()

def start():
    window = webview.create_window(title='Vision', url="home.html", zoomable=False, frameless=False, resizable=False, draggable=True, easy_drag=True, height=600, width=1010, background_color="#0f0f10")
    window.expose(execute)
    window.expose(attach)
    webview.start()

def execute(text):
    VisionAPI.Execute(text)

def attach():
    VisionAPI.Inject()

if __name__ == '__main__':
    start()
