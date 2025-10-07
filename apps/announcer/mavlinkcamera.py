# Disable "Bare exception" warning
# pylint: disable=W0702
import threading
import time
import bs4
import logging
from threading import Event
from pymavlink import mavutil
from pymavlink.dialects.v20 import common
from pymavlink.dialects.v20.common import CAMERA_CAP_FLAGS_HAS_VIDEO_STREAM
#from pymavlink.dialects.v20.common import CAMERA_CAP_FLAGS_CAPTURE_VIDEO, CAMERA_CAP_FLAGS_HAS_BASIC_ZOOM
MAV_CMD_REQUEST_VIDEO_START_STREAM = 2502
MAV_CMD_REQUEST_VIDEO_STOP_STREAM = 2503
MAV_CMD_REQUEST_VIDEO_STREAM_INFORMATION = 2504
MAV_CMD_REQUEST_VIDEO_STREAM_STATUS = 2505
MAV_CMD_REQUEST_CAMERA_SETTINGS = 522
MAV_CMD_REQUEST_STORAGE_INFORMATION = 525
MAV_CMD_REQUEST_CAMERA_CAPTURE_STATUS = 527
MAV_CMD_SET_CAMERA_ZOOM = 531

_boot = time.time()

class MavlinkCameraManager(threading.Thread):
    param_map = {}
    param_types = {}
    _kill: Event = None

    def __init__(self, camera_id=1, camera_name="video", rtspstream=None, system_host="127.0.0.1", system_port="14561", system_id=1):
        super().__init__()
        self.rtspstream = rtspstream.encode("ascii") if rtspstream else None
        self.camera_id = camera_id
        self.camera_name = camera_name
        self.system_host = system_host
        self.system_port = system_port
        self.system_id = system_id
        logging.info("Mavlink ready to go")
        self._kill = Event()

    @property
    def is_alive(self):
        return not self._kill.is_set()

    def stop(self):
        if not self.is_alive:
            return  # already dead

        if self._kill is not None:
            self._kill.set()

    def wait_conn(self):
        """
        Sends heartbeat to establish the UDP communication and awaits for a response
        """
        msg = None
        attempts = 0
        max_attempts = 10
        while not msg and attempts < max_attempts:
            self.send_heartbeat()
            msg = self.master.recv_match(timeout=0.5)
            attempts += 1
            time.sleep(0.5)
        
        if msg:
            logging.info(f"Connection established after {attempts} attempts")
        else:
            logging.warning(f"No response after {attempts} attempts, continuing anyway")

    def mavlink_type(self, xml_type):
        if xml_type == "int32":
            return mavutil.mavlink.MAV_PARAM_EXT_TYPE_INT32
        elif xml_type == "uint32":
            return mavutil.mavlink.MAV_PARAM_EXT_TYPE_UINT32
        elif xml_type == "bool":
            return mavutil.mavlink.MAV_PARAM_EXT_TYPE_UINT8

    def as_128_bytes(self, value, param_type):
        """returns values as 128 bytes"""
        if param_type == "int32":
            small = value.to_bytes(4, "little", signed=True)
            r = self.makebytes(small,128)
            logging.debug(value, param_type, " = " , r)
            return r
        if "uint" in param_type or param_type == "bool":
            return value.to_bytes(128, "little")

    def read_param(self, param_id):
        """ Read a param and return it as a PARAM_EXT_VALUE message """
        # Check if we have the parameters map cached, create if if we don't
        if len(self.param_map.keys()) == 0:
            with open("camera_definitions/example.xml") as f:
                soup = bs4.BeautifulSoup(f.read(), "lxml")
                parameters = soup.find_all("parameter")
                for parameter in parameters:
                    self.param_map[parameter["name"]] = int(parameter["v4l2_id"])
                    self.param_types[parameter["name"]] = parameter["type"]

        # grab v4l2 id equivalent of param_id
        v4l2_id = self.param_map[param_id]
        # read actual value of v4l2 control
        value = self.control.get_control_value(v4l2_id)
        logging.debug("read: ", param_id, " = ", value)
        # mav v4l2 type to xml type
        param_type = self.param_types[param_id]
        # send param_ext_value
        self.master.mav.param_ext_value_send(
            self.makestring(param_id.encode("utf-8"), 16),
            self.as_128_bytes(value, param_type),
            self.mavlink_type(param_type),
            1,
            0
        )

    def set_param(self, raw_msg):
        """Set a Camera param via mavlink"""
        msg = raw_msg.to_dict()
        param_id = msg["param_id"]
        param_type = self.param_types[param_id]
        # unpack value from 128 bytes
        value = self.convert_value(param_type, raw_msg.get_payload())
        v4l2_id = self.param_map[param_id]
        logging.debug("setting ", param_id, param_type,  "to ", value)
        # Set value
        self.control.set_control_value(v4l2_id, value)
        value = self.control.get_control_value(v4l2_id)
        # Send new value to GCS
        self.master.mav.param_ext_ack_send(
            self.makestring(param_id.encode("utf-8"), 16),
            self.as_128_bytes(value, param_type),
            self.mavlink_type(self.param_types[param_id]),
            mavutil.mavlink.PARAM_ACK_ACCEPTED
        )

    def convert_value(self, type, payload):
        """unpacks value from 128 bytes payload"""
        relevant = payload[22:26]
        if type == "uint8":
            return int.from_bytes(relevant, byteorder="little", signed=False)
        elif type == "int32":
            return int.from_bytes(relevant, byteorder="little", signed=True)
        elif type == "uint32":
            return int.from_bytes(relevant, byteorder="little", signed=False)
        logging.debug("oops", type)
        return int.from_bytes(relevant, byteorder="little", signed=True)

    def run(self):
        logging.info("Mavlink starting")
        conn = f'udpout:{self.system_host}:{self.system_port}'
        logging.debug(conn)
        self.master = mavutil.mavlink_connection(conn,
                                                 source_system=self.system_id,
                                                 source_component=self.camera_id,
                                                 dialect='standard')

        # required?
        self.wait_conn()

        hb: int = 0
        logging.debug("Mavlink thread started")
        while self.is_alive:
            try:
                raw_msg = self.master.recv_match()
                msg = raw_msg.to_dict()
                if msg["mavpackettype"] == "COMMAND_LONG":
                    
                    src_system = raw_msg._header.srcSystem
                    src_component = raw_msg._header.srcComponent

                    if msg["command"] == mavutil.mavlink.MAV_CMD_REQUEST_CAMERA_INFORMATION:
                        logging.debug(f"Got MAV_CMD_REQUEST_CAMERA_INFORMATION (Camera ID: {self.camera_id})")
                        self.master.mav.command_ack_send(common.MAV_CMD_REQUEST_CAMERA_INFORMATION,
                                                         common.MAV_RESULT_ACCEPTED,
                                                         target_system=src_system,
                                                         target_component=src_component)
                        logging.debug(f"Send INFO (Camera ID: {self.camera_id})")
                        self.send_camera_information()
                    elif msg["command"] == MAV_CMD_REQUEST_VIDEO_STREAM_INFORMATION:
                        logging.debug(f"Got MAV_CMD_REQUEST_VIDEO_STREAM_INFORMATION (Camera ID: {self.camera_id})")
                        self.master.mav.command_ack_send(MAV_CMD_REQUEST_VIDEO_STREAM_INFORMATION,
                                                         common.MAV_RESULT_ACCEPTED,
                                                         target_system=src_system,
                                                         target_component=src_component)
                        self.send_video_stream_information()
                    elif msg["command"] == MAV_CMD_REQUEST_CAMERA_SETTINGS:
                        self.master.mav.command_ack_send(MAV_CMD_REQUEST_CAMERA_SETTINGS,
                                                         common.MAV_RESULT_ACCEPTED,
                                                         target_system=src_system,
                                                         target_component=src_component)
                        logging.debug(f"Got MAV_CMD_REQUEST_CAMERA_SETTINGS (Camera ID: {self.camera_id})")
                        self.send_camera_settings()
                    elif msg["command"] == MAV_CMD_REQUEST_VIDEO_STREAM_STATUS:
                        self.master.mav.command_ack_send(MAV_CMD_REQUEST_VIDEO_STREAM_STATUS,
                                                         common.MAV_RESULT_ACCEPTED,
                                                         target_system=src_system,
                                                         target_component=src_component)
                        logging.debug(f"Got MAV_CMD_REQUEST_VIDEO_STREAM_STATUS (Camera ID: {self.camera_id})")
                        self.send_stream_status()
                    elif msg["command"] == MAV_CMD_SET_CAMERA_ZOOM:
                        self.master.mav.command_ack_send(MAV_CMD_SET_CAMERA_ZOOM,
                                                         common.MAV_RESULT_ACCEPTED,
                                                         target_system=src_system,
                                                         target_component=src_component)
                        logging.debug(f"Got MAV_CMD_SET_CAMERA_ZOOM (Camera ID: {self.camera_id})")
                    elif msg["command"] == MAV_CMD_REQUEST_CAMERA_CAPTURE_STATUS:
                            logging.debug(f"Got MAV_CMD_REQUEST_CAMERA_CAPTURE_STATUS (Camera ID: {self.camera_id})")
                            self.master.mav.command_ack_send(MAV_CMD_REQUEST_CAMERA_CAPTURE_STATUS,
                                                             common.MAV_RESULT_UNSUPPORTED,
                                                             target_system=src_system,
                                                             target_component=src_component)
                    elif msg["command"] == MAV_CMD_REQUEST_STORAGE_INFORMATION:
                        logging.debug(f"Got 'MAV_CMD_REQUEST_STORAGE_INFORMATION' from GCS (Camera ID: {self.camera_id})")
                        self.master.mav.command_ack_send(MAV_CMD_REQUEST_STORAGE_INFORMATION,
                                                         common.MAV_RESULT_ACCEPTED,
                                                         target_system=src_system,
                                                         target_component=src_component)
                    else:
                        logging.debug(msg)

                elif msg["mavpackettype"] == "PARAM_EXT_REQUEST_READ":
                    logging.warning("PARAM_EXT_REQUEST_READ not supported - self.control not initialized")
                    # self.read_param(msg['param_id'])  # Disabled: self.control not initialized
                elif msg["mavpackettype"] == "PARAM_EXT_SET":
                    logging.warning("PARAM_EXT_SET not supported - self.control not initialized")
                    # self.set_param(raw_msg)  # Disabled: self.control not initialized
            except AttributeError as e:
                if "NoneType" not in str(e):
                    logging.debug(e)

            time.sleep(0.1)
            hb += 1
            if hb % 10 == 0:
                self.send_heartbeat()

    def send_heartbeat(self):
        self.master.mav.heartbeat_send(
            0,
            mavutil.mavlink.MAV_TYPE_CAMERA,
            mavutil.mavlink.MAV_AUTOPILOT_GENERIC,
            0,
            mavutil.mavlink.MAV_STATE_STANDBY,
            3
        )

    def makestring(self, string, size):
        """ returns a 16 bytes long string"""
        raw = bytearray(size)
        for i, char in enumerate(string):
            raw[i] = char
        return raw

    def makebytes(self, string, size):
        """returns a size-sized bytes bytearray"""
        raw = bytearray(size)
        for i, char in enumerate(string):
            raw[size -(len(string)) + i] = char
        return raw

    def send_camera_information(self):
        self.master.mav.camera_information_send(
            self._boot_ts(),
            self.makestring(self.camera_name.encode("ascii"), 32),
            self.makestring(self.camera_name.encode("ascii"), 32),
            1,
            0.0,
            0.0,
            0.0,
            1280,
            720,
            1,
            CAMERA_CAP_FLAGS_HAS_VIDEO_STREAM,#CAMERA_CAP_FLAGS_CAPTURE_VIDEO | CAMERA_CAP_FLAGS_HAS_VIDEO_STREAM | CAMERA_CAP_FLAGS_HAS_BASIC_ZOOM,
            0,
            self.makestring(b"_XXX", 140)
        )

    def send_camera_settings(self):
        self.master.mav.camera_settings_send(
            self._boot_ts(),
            1,
            1.0,
            1.0
        )

    def send_stream_status(self):
        self.master.mav.video_stream_status_send(
            1,
            mavutil.mavlink.VIDEO_STREAM_STATUS_FLAGS_RUNNING,
            0.0,
            1280,
            720,
            5000,
            0,
            63
        )

    def send_video_stream_information(self):
        # Handle None rtspstream case
        rtsp_bytes = self.rtspstream if self.rtspstream is not None else b""
        self.master.mav.video_stream_information_send(
            1,
            1,
            mavutil.mavlink.VIDEO_STREAM_TYPE_RTSP,
            mavutil.mavlink.VIDEO_STREAM_STATUS_FLAGS_RUNNING,
            30,
            1280,
            720,
            5000,
            0,
            63,
            self.makestring(self.camera_name.encode("ascii"), 32),
            self.makestring(rtsp_bytes, 160),
        )

    @staticmethod
    def _boot_ts():
        return int(time.time() - _boot)
