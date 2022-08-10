#!/usr/bin/python3
import os
from signal import signal, SIGINT, SIGTERM
import logging
from typing import Any
from mavlinkcamera import MavlinkCameraManager

mavlink: Any = None

def run_service():
    global mavlink
    stream_url = os.environ['CAMERA_URL']
    camera_id = int(os.environ['CAMERA_ID'])
    camera_name = os.environ['CAMERA_NAME']
    system_host = os.environ['SYSTEM_HOST']
    system_port=os.environ['SYSTEM_PORT']
    system_id = int(os.environ['SYSTEM_ID'])
    

    mavlink = MavlinkCameraManager(rtspstream=stream_url, camera_id=camera_id, camera_name=camera_name, system_host=system_host, system_port=system_port, system_id=system_id)
    mavlink.start()
    mavlink.join()


def handler(signal_received, frame):
    global mavlink
    # Handle any cleanup here
    logging.info('SIGINT, SIGTERM or CTRL-C detected. Exiting gracefully')
    mavlink.stop()


if __name__ == '__main__':
    logging.basicConfig()
    logging.getLogger().setLevel(logging.DEBUG)
    signal(SIGINT, handler)
    signal(SIGTERM, handler)
    run_service()
