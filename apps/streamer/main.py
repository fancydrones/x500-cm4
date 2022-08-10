#!/usr/bin/python3
import os
from signal import signal, SIGINT, SIGTERM
import logging
import gi
from gi.repository import Gst, GstRtspServer, GLib
from typing import Any

#Initializes the GStreamer library, setting up internal path lists, registering built-in elements, and loading standard plugins.
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')

Gst.init(None)

service: Any = None

class GstServer(GstRtspServer.RTSPServer):
    def __init__(self, pipeline0=None, pipeline1=None, pipeline2=None, port=8554, **properties):
        super(GstServer, self).__init__(**properties)
        Gst.init(None)
        self.pipeline0 = pipeline0
        self.pipeline1 = pipeline1
        self.pipeline2 = pipeline2
        self.set_service(str(port))
        self.mainloop = None
        #Gst.debug_set_active(True)
        #Gst.debug_set_default_threshold(3)

    def run(self):
        logging.info("RTSP server starting")

        if self.pipeline0 is None:
            self.pipeline0 = 'videotestsrc pattern=ball ! video/x-raw,width=640,height=480 ! videoconvert ! x264enc bitrate=50000 ! video/x-h264, profile=baseline !rtph264pay config-interval=1 name=pay0 pt=96'

        if self.pipeline1 is None:
            self.pipeline1 = 'videotestsrc pattern=snow ! video/x-raw,width=640,height=480 ! videoconvert ! x264enc bitrate=50000 ! video/x-h264, profile=baseline !rtph264pay config-interval=1 name=pay0 pt=96'
        
        if self.pipeline0 is not None:
            logging.debug(f'Starting pipeline0: {self.pipeline0}')
            self.factory0 = GstRtspServer.RTSPMediaFactory()
            self.factory0.set_launch(self.pipeline0)
            self.factory0.set_shared(True)

        if self.pipeline1 is not None:
            logging.debug(f'Starting pipeline1: {self.pipeline1}')
            self.factory1 = GstRtspServer.RTSPMediaFactory()
            self.factory1.set_launch(self.pipeline1)
            self.factory1.set_shared(True)

        if self.pipeline2 is not None:
            logging.debug(f'Starting pipeline2: {self.pipeline2}')
            self.factory2 = GstRtspServer.RTSPMediaFactory()
            self.factory2.set_launch(self.pipeline2)
            self.factory2.set_shared(True)

        if self.pipeline0 is not None:
            self.get_mount_points().add_factory("/video0", self.factory0)
        if self.pipeline1 is not None:
            self.get_mount_points().add_factory("/video1", self.factory1)
        if self.pipeline2 is not None:
            self.get_mount_points().add_factory("/video2", self.factory2)
                   
        self.attach(None)
        self.mainloop = GLib.MainLoop()
        logging.info("RTSP server starting main loop")
        self.mainloop.run()

    def stop(self):
        self.mainloop.quit()

def run_service():
    global service
    if 'CAMERA_PIPELINE0' in os.environ:
        stream_pipeline0 = os.environ['CAMERA_PIPELINE0']
    else:
        stream_pipeline0 = None

    if 'CAMERA_PIPELINE1' in os.environ:
        stream_pipeline1 = os.environ['CAMERA_PIPELINE1']
    else:
        stream_pipeline1 = None

    if 'CAMERA_PIPELINE2' in os.environ:
        stream_pipeline2 = os.environ['CAMERA_PIPELINE2']
    else:
        stream_pipeline2 = None

    if 'VIDEO_PORT' in os.environ:
        video_port=os.environ['VIDEO_PORT']
    else:
        video_port=8554

    stream=GstServer(pipeline0=stream_pipeline0, pipeline1=stream_pipeline1, pipeline2=stream_pipeline2, port=video_port)
    stream.run()


def handler(signal_received, frame):
    global service
    # Handle any cleanup here
    logging.info(str(signal_received) + ' detected. Exiting gracefully')
    service.stop()


if __name__ == '__main__':
    logging.basicConfig()
    logging.getLogger().setLevel(logging.DEBUG)
    signal(SIGINT, handler)
    signal(SIGTERM, handler)
    run_service()
