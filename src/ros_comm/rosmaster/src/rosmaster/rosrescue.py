"""
ROS Rescue

This module serves as a fault tolerance mechanism for single point of failure in ros master
The architecture is inspired from Google file system
"""
import rospkg
import os
import yaml
import io
import rosmaster.exceptions
from rosmaster.util import xmlrpcapi

try:
    from urllib.parse import urlparse
except ImportError:
    from urlparse import urlparse

try:
    from xmlrpc.client import Fault, ProtocolError, ServerProxy
except ImportError:
    from xmlrpclib import Fault, ProtocolError, ServerProxy
from rospkg.environment import ROS_LOG_DIR

CHKPT_PATH=""

class RosRescue(object):

    PUBLISHERS = "PUBLISHERS"
    SUBSCRIBERS = "SUBSCRIBERS"
    SERVICES = "SERVICES"
    PARAM_SUBSCRIBERS = "PARAM_SUBSCRIBERS"
    NODES = "NODES"

    def __init__(self , regman):
        global CHKPT_PATH
        print("rescue Object created")
        env = os.environ
        log_dir = rospkg.get_log_dir(env=env)
        CHKPT_PATH = os.path.join(log_dir, "latest-chkpt.yaml")
        self.regman = regman
        self.recovering= False
        return

    def to_yaml_dict(self, registration):
        """

        @param registration: One of the Registration instances
        @type registration : Registrations
        @return: a dictionary to dump into yaml file
        @type : dict
        """
        registration_yaml={}
        typ=""
        from rosmaster.registrations import Registrations
        if registration.type ==  Registrations.TOPIC_SUBSCRIPTIONS:
            typ = RosRescue.SUBSCRIBERS
            registration_yaml = {typ: registration.map}
        elif registration.type == Registrations.TOPIC_PUBLICATIONS:
            typ = RosRescue.PUBLISHERS
            registration_yaml = {typ: registration.map}
        elif registration.type == Registrations.PARAM_SUBSCRIPTIONS:
            typ = RosRescue.PARAM_SUBSCRIBERS
            registration_yaml = {typ: registration.map}
        elif registration.type == Registrations.SERVICE:
            typ = RosRescue.SERVICES
            service_dict = { "map" : registration.map , "service_api_map" : registration.service_api_map}
            registration_yaml = {typ: service_dict}

        else:
            raise rosmaster.exceptions.InternalException("invalid registration type: %s for CHECKPOINTING"%registration.type)
            return {}

        #print(registration.map)
        return registration_yaml

    def nodes_to_yaml_dict(self, nodes):
        return {RosRescue.NODES: nodes}

    def registration_parser(self, regman):
        data=[]
        data.append(self.nodes_to_yaml_dict(regman.nodes))
        data.append(self.to_yaml_dict(regman.publishers))
        data.append(self.to_yaml_dict(regman.subscribers))
        data.append(self.to_yaml_dict(regman.param_subscribers))
        data.append(self.to_yaml_dict(regman.services))
        return data

    """ 
    Method which saves the state of the Master Registrations 
    """

    def saveState(self):
        with io.open(CHKPT_PATH , 'w', encoding='utf8') as outfile:
            data = self.registration_parser(self.regman)
            yaml.dump_all(data, outfile, default_flow_style=False, allow_unicode=True)
        outfile.close()
        print("Ros Rescue saved the Master state")
        return

    def loadState(self):
        return

    def get_live_nodes(self, nodemap):
        live_nodes ={}
        for caller_id , noderef_obj in nodemap.items():
            try:
                #proxy = xmlrpcapi(noderef_obj.api)
                uri = noderef_obj.api
                if uri is None:
                    return None
                uriValidate = urlparse(uri)
                if not uriValidate[0] or not uriValidate[1]:
                    return None
                proxy = ServerProxy(uri)
                proxy.getName("/master")
                live_nodes[caller_id] = proxy
                print("live node : "+ caller_id)
            except Fault as e:
                print ("Fault code: %d" % e.faultCode)
                print ("Fault string: %s" % e.faultString)
            except ProtocolError as e:
                print "A protocol error occurred"
                print "URL: %s" % e.url
                print "HTTP/HTTPS headers: %s" % e.headers
                print "Error code: %d" % e.errcode
                print "Error message: %s" % e.errmsg
            except Exception as e:
                print ("Node :"+caller_id+"Has died")
        return live_nodes


    def recover_master( self, reg_typ , reg_map , live_nodes):
        print("REGISTRATION TYPE:" + reg_typ)
        temp_map = reg_map
        reg_func=None

        if reg_typ == RosRescue.SERVICES :
            service_api_map = reg_map.get("service_api_map")
            temp_map = reg_map.get("map")
            if service_api_map is None :
                return
            m={}
            for s, caller_tup in service_api_map.items():
                 temp_tup  = temp_map.get(s)[0]
                 m[s] = [(temp_tup[0] , temp_tup[1] , caller_tup[1])]
            temp_map = m
            reg_func = self.regman.register_service

        if reg_typ == RosRescue.PUBLISHERS :
            reg_func = self.regman.register_publisher
        elif reg_typ == RosRescue.SUBSCRIBERS :
            reg_func = self.regman.register_subscriber
        elif reg_typ == RosRescue.SERVICES:
            reg_func = self.regman.register_service
        else :
            print("Not supported")
            return

        for t, caller_tup_list in temp_map.items():
            for caller_tup in caller_tup_list:
                #check if the caller id exists in the live live_nodes
                proxy = live_nodes.get(caller_tup[0], None)
                if proxy is not None :
                    if reg_typ == RosRescue.PUBLISHERS :
                        code, _, pubs = proxy.getPublications('/master')
                    elif reg_typ == RosRescue.SUBSCRIBERS :
                        code, _, pubs = proxy.getSubscriptions('/master')
                    elif reg_typ == RosRescue.SERVICES :
                        reg_func(t, caller_tup[0], caller_tup[1], caller_tup[2])
                        continue

                    if t in [ tname for [tname,ttype] in pubs] :
                        reg_func(t, caller_tup[0], caller_tup[1])
                    else :
                        print("Node "+caller_tup[0]+ "does not have topic "+t+"Any more")
                else :
                    print("Node "+caller_tup[0]+" is NO More")
        return

    def getLastSavedState(self):
        self.recovering = True
        if os.path.exists(CHKPT_PATH):
            with open(CHKPT_PATH) as f:
                d = yaml.load_all(f)
                live_nodes={}
                for doc in d :
                    for k,v in doc.items():
                        if k == RosRescue.NODES :
                            live_nodes = self.get_live_nodes(v)
                        else :
                            self.recover_master(k , v, live_nodes)
        return



