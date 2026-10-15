"""Bridge Windows IPv6 loopback to WSL's IPv4-only local service listeners.

ADB reverse may resolve localhost to ::1. No LAN listener, transcript logging,
credential changes or request rewriting. Exit after 30 minutes.
"""
import select
import socket
import socketserver
import threading

class Bridge(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            with socket.create_connection(('127.0.0.1',self.server.server_address[1]),timeout=10) as upstream:
                peers={self.request:upstream,upstream:self.request}
                readable=list(peers)
                while readable:
                    ready,_,_=select.select(readable,[],[],120)
                    if not ready:
                        return
                    for source in ready:
                        data=source.recv(65536)
                        if data:
                            peers[source].sendall(data)
                        else:
                            readable.remove(source)
                            peers[source].shutdown(socket.SHUT_WR)
        except OSError:
            return

class Server(socketserver.ThreadingTCPServer):
    address_family=socket.AF_INET6
    allow_reuse_address=True
    daemon_threads=True

if __name__=='__main__':
    servers=[]
    try:
        for port in (8766,8767,8768):
            server=Server(('::1',port),Bridge)
            servers.append(server)
            threading.Thread(target=server.serve_forever,daemon=True).start()
        threading.Event().wait(1800)
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()
