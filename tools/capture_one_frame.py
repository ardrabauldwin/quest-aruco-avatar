import socket
from pathlib import Path
import cv2
import numpy as np


def receive_all(connection, size):
    data = bytearray()
    while len(data) < size:
        packet = connection.recv(size - len(data))
        if not packet:
            raise ConnectionError("camera stream closed")
        data.extend(packet)
    return bytes(data)


with socket.create_server(("127.0.0.1", 7007)) as server:
    server.settimeout(30)
    connection, _ = server.accept()
    with connection:
        header = receive_all(connection, 16)
        width = int.from_bytes(header[0:4], "big")
        height = int.from_bytes(header[4:8], "big")
        image_format = int.from_bytes(header[8:12], "big")
        size = int.from_bytes(header[12:16], "big")
        pixels = np.frombuffer(receive_all(connection, size), dtype=np.uint8)
        if image_format == 2:
            image = pixels.reshape((height, width))
        elif image_format == 5:
            image = cv2.cvtColor(
                pixels.reshape((height, width, 4)), cv2.COLOR_RGBA2BGR
            )
        else:
            raise ValueError(f"unsupported image format {image_format}")
        output = Path(__file__).with_name("quest_camera_frame.png")
        if not cv2.imwrite(str(output), image):
            raise OSError(f"could not save {output}")
