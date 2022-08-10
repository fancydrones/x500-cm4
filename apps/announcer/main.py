#!/usr/bin/python3
import os
from signal import signal, SIGINT, SIGTERM, SIGQUIT
import logging
from typing import Any
from mavlinkcamera import MavlinkCameraManager

service: Any = None

def run_service():
    global service
    stream_url = os.environ['CAMERA_URL']
    camera_id = int(os.environ['CAMERA_ID'])
    camera_name = os.environ['CAMERA_NAME']
    system_host = os.environ['SYSTEM_HOST']
    system_port=os.environ['SYSTEM_PORT']
    system_id = int(os.environ['SYSTEM_ID'])
    

    service = MavlinkCameraManager(rtspstream=stream_url, camera_id=camera_id, camera_name=camera_name, system_host=system_host, system_port=system_port, system_id=system_id)
    service.start()
    service.join()


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
    signal(SIGQUIT, handler)
    run_service()
