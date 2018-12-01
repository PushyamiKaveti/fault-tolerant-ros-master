
#Pushyami Kaveti : ros master discovery and restart signal
import os
import rospy
import threading
import rosgraph
import subprocess
import socket

from rospy.core import xmlrpcapi
try:
    import urllib.parse as urlparse #Python 3.x
except ImportError:
    import urlparse


MASTER_CHECK_INTERVAL = 1.0
#rosmaster params
NUM_WORKERS=3
PORT = 11311


def get_master_uri():
    uri = None
    try:
        uri = rosgraph.rosenv.get_master_uri()
    except:
        uri = os.environ['ROS_MASTER_URI']
    hostname = socket.gethostname()
    if hostname and uri and not hostname == 'localhost' and 'localhost' in uri:
        return 'http://%s:%s/' % (hostname, PORT)

#code taken from rospy module. used here for convenience
def get_master_xmlrpcapi(uri):
   return xmlrpcapi(uri)

def get_port(url):
    if url is None:
        return None
    o = urlparse.urlparse(url)
    return o.port


class RosMasterMonitor(object):

    def __init__(self, interval):
        self.CHECK_INTERVAL = interval
        self.master_uri = get_master_uri()
        self._master = get_master_xmlrpcapi(self.master_uri)
        # timer to check for the ros master
        self.discoverThread = threading.Timer(interval, self.discover_master)

    def start(self):
        self.discoverThread.start()

    def is_master_alive(self):
        code = -1
        if self.master_uri is None or self._master is None:
            print("ERROR HAD OCCURED IN INITIALIZATION")
            self.master_uri = get_master_uri()
            self._master = get_master_xmlrpcapi(self.master_uri)
        try:
            code, _, master_uri = self._master.getUri(rospy.get_name())
            if code == 1:
                if master_uri == self.master_uri:
                    return True
        except Exception as e :
            return False
        return False

    def restart_rosmaster(self):
        package = 'rosmaster'
        port = get_port(self.master_uri)
        args = [package, '--core', '-p', str(port), '-w', str(NUM_WORKERS), '--rescue']
        try:
            popen = subprocess.Popen(args, close_fds=True, preexec_fn=os.setsid)
        except OSError as e:
            print("OSError(%d, %s)", e.errno, e.strerror)

        poll_result = popen.poll()
        if poll_result is None or poll_result == 0:
            print("process[%s]: started with pid [%s]" % (package, popen.pid))
            return True
        else:
            print("failed to start local process: %s" % (' '.join(args)))
            return False

    def discover_master(self):
        """
        This Method keeps setting the timer as long it finds the master.
        When it is unable to connect to master it will call the rosmaster script and restart.
        :return:
        """

        if not rospy.is_shutdown() :
            #see if the master is still running
            if not self.is_master_alive() :
                print("MASTER FAILURE DETECTED. Restarting the Master")
                if not self.restart_rosmaster():
                    return

            # Finally , restart the time for checking ros master
            self.discoverThread = threading.Timer(self.CHECK_INTERVAL, self.discover_master)
            self.discoverThread.start()


def ros_moniter_main():
    print("ROS MONITOR STARTED")
    rospy.init_node("rosmaster_monitor", anonymous=True)

    #create the RosMaster Monitor Object to keep track of the master and restart when needed
    ros_mon = RosMasterMonitor(MASTER_CHECK_INTERVAL)
    ros_mon.start()
    rospy.spin()