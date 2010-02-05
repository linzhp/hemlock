package com.mintdigital.hemlock.conn {
    import com.mintdigital.hemlock.HemlockEnvironment;
    import com.mintdigital.hemlock.Logger;
    import com.mintdigital.hemlock.data.JID;
    import com.mintdigital.hemlock.data.Message;
    import com.mintdigital.hemlock.data.Presence;
    import com.mintdigital.hemlock.events.ChallengeEvent;
    import com.mintdigital.hemlock.events.ConnectionEvent;
    import com.mintdigital.hemlock.events.FeaturesEvent;
    import com.mintdigital.hemlock.events.MessageEvent;
    import com.mintdigital.hemlock.events.PresenceEvent;
    import com.mintdigital.hemlock.events.RegistrationEvent;
    import com.mintdigital.hemlock.events.SessionEvent;
    import com.mintdigital.hemlock.events.StreamEvent;
    
    import org.jivesoftware.xiff.core.XMPPSocketConnection;
    import org.jivesoftware.xiff.data.IQ;
    import org.jivesoftware.xiff.data.XMPPStanza;
    import org.jivesoftware.xiff.events.ConnectionSuccessEvent;
    import org.jivesoftware.xiff.events.LoginEvent;
    import org.jivesoftware.xiff.events.IQEvent;
    import org.jivesoftware.xiff.exception.SerializationException;
    import org.jivesoftware.xiff.util.SocketDataEvent;
    import org.jivesoftware.xiff.util.SocketConn;
	import org.jivesoftware.xiff.data.IExtension;
    import flash.errors.IOError;
    import flash.events.ProgressEvent;
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.events.TimerEvent;
    import flash.system.Security;
    import flash.xml.XMLDocument;
    import flash.xml.XMLNode;
    import flash.utils.Timer;
   
    
    public class XMPPConnection extends XMPPSocketConnection{
        
        protected var _incompleteRawXML : String;
        protected var _pendingIQs : Object;
        private var _keepAliveTimer:Timer;
            
        public function XMPPConnection(){
            Security.loadPolicyFile('xmlsocket://'
                + HemlockEnvironment.SERVER + ':' + HemlockEnvironment.POLICY_PORT);

            super();
            
            port = 5222;
        }
        
        override public function connect(streamType:String = "standard") : Boolean {
            try{
                _incompleteRawXML = '';
                _pendingIQs = new Object();

            	super.connect(streamType);
                Logger.debug('XMPPConnection::connect : socket = ' + binarySocket);
            }catch(error:SecurityError){
                Logger.error('XMPPConnection::connect : Could not connect. Error = ' + error);
                return false;
            }
            
            return true;
        }
        
        override public function disconnect() : void {
            Logger.debug("XMPPConnection::disconnect()");
            super.disconnect();
            _keepAliveTimer.stop();
            dispatchEvent(new ConnectionEvent(ConnectionEvent.DESTROY));
        }
        
        public function sendRawString( data:* ):void{
            Logger.debug("Sending..." + data);
            sendXML(data);
            resetKeepAliveTimer();
        }
        
        public function sendOpenStreamTag() : void {
            Logger.debug("XMPPConnection::sendOpenStreamTag()");
            sendRawString( openStreamTag() );
        }
        
        public function sendStanza( stanza:XMPPStanza ):void
        {
            Logger.debug("XMPPConnection::sendStanza()");
            if ( _active ) {
                if ( stanza is IQ ) {
                    var iq:IQ = stanza as IQ;
                    if ( ( iq.callback != null ) || ( iq.callbackName != null && iq.callbackScope != null ) ) {
            	        _pendingIQs[iq.id] = {methodName:iq.callbackName, methodScope:iq.callbackScope, func:iq.callback};
                    }
                }
                var root:XMLNode = stanza.getNode().parentNode;
                if ( root == null ) {
                    root = new XMLDocument();
                }
                 if ( stanza.serialize( root ) ) {
                    sendRawString( root.firstChild );
                } else {
                    throw new SerializationException();
                }
            }
        }
        
        //--------------------------------------
        //  Event dispatchers
        //--------------------------------------
        
        private function handleStreamStart(node:XMLNode):void{
            Logger.debug("XMPPConnection::handleStreamStart() " );
            dispatchEvent(new StreamEvent(StreamEvent.START, {
                bubbles:    true,
                cancelable: true,
                connection: this,
                node:       node
            }));
        }
        
        //TODO integrate with super
        override protected function handleStreamError( node:XMLNode ):void{
            Logger.debug('XMPPConnection::handleStreamError()');
            dispatchEvent(new StreamEvent(StreamEvent.ERROR, {
                bubbles:    true,
                cancelable: true,
                connection: this
            }));
        }
        
        //TODO integrate with super
		override protected function handleMessage( node:XMLNode ):org.jivesoftware.xiff.data.Message{
            Logger.debug("XMPPConnection::handleMessage() " );
            Logger.debug('- node.id = ' + node.attributes.id);
            
            var incomingPayloadType:String;
            
            if (node.attributes.id) {
                incomingPayloadType = node.attributes.id.split(Message.PAYLOAD_TYPE_DELIMITER)[0];
            };
            
            var message:Message = new Message({
                payloadType: incomingPayloadType
                    // Preserve payloadType from original node's ID
            });

            // Populate the Message with the incoming data
            Logger.debug('XMPPConnection::handleMessage() : before message.deserialize(node)');
            if( !message.deserialize( node ) ) {
                throw new SerializationException();
            }
            Logger.debug('XMPPConnection::handleMessage() : after message.deserialize(node)');
            
            dispatchEvent(new MessageEvent(MessageEvent.CHAT_MESSAGE, {
                to:             new JID(node.attributes.to),
                from:           new JID(node.attributes.from),
                xmppMessage:    message
            }));
            return message;
        }
        
		override protected function handlePresence( node:XMLNode ):org.jivesoftware.xiff.data.Presence{
			
            Logger.debug('XMPPConnection::handlePresence() ' + node);
            var presence:Presence = new Presence();
            
            if (!presence.deserialize(node)){
                throw new SerializationException();
            }
            dispatchEvent(new PresenceEvent(PresenceEvent.UPDATE, {
                presence: presence
            }));
            return super.handlePresence(node);
        }

        private function handleChallenge(node:XMLNode) : void {
            Logger.debug("XMPPConnection::handleChallenge() " );
            dispatchEvent(new ChallengeEvent(ChallengeEvent.CHALLENGE, {
                bubbles: true,
                cancelable : true,
                connection: this,
                node: node
            }));
        }
        
        public function handleRegisterResponse(packet:IQ):void {
            Logger.debug("XMPPConnection::handleRegisterResponse()");
            dispatchEvent(new RegistrationEvent(RegistrationEvent.REGISTERING, {
                iq: packet
            }));
        }
        
        private function handleSuccess() : void {
            Logger.debug("XMPPConnection::handleSuccess()");
            dispatchEvent(new LoginEvent());
            dispatchEvent(new SessionEvent(SessionEvent.CREATE_SUCCESS));
        }
        
        private function handleFailure(node:XMLNode) : void {
            Logger.debug("XMPPConnection::handleFailure()");
            for ( var i:int = 0; i < node.childNodes.length; i++ ) {
                Logger.debug("Failure message: " + node.childNodes[i].nodeName);
            };
            dispatchEvent(new SessionEvent(SessionEvent.CREATE_FAILURE));
        }
        
        private function handleFeatures(node:XMLNode) : void {
            Logger.debug('XMPPConnection::handleFeatures()');
            dispatchEvent(new FeaturesEvent(FeaturesEvent.FEATURES, {
                bubbles:    true,
                cancelable: true,
                connection: this,
                node:       node
            }));
        }

		override protected function handleIQ( node:XMLNode ):IQ
        {
            var iq:IQ = new IQ();
            if( !iq.deserialize( node ) ) {
                throw new SerializationException();
            }
            // handle error
            if( iq.type == IQ.ERROR_TYPE && !_pendingIQs[iq.id] ) {
                Logger.error("XMPPConnection::handleIQ() : ERROR, no registered id:" + iq.id );//different from supper.handleIQ only in this line
            }
            else {
                // check if a callback exists for this iq
                if ( _pendingIQs[iq.id] !== undefined ) {
                    var callbackInfo:* = _pendingIQs[iq.id];
                    if ( callbackInfo.methodScope && callbackInfo.methodName ) {
                        callbackInfo.methodScope[callbackInfo.methodName].apply( callbackInfo.methodScope, [iq] );
                    }
                    if (callbackInfo.func != null) { 
                        callbackInfo.func( iq );
                    }
                    _pendingIQs[iq.id] = null;
                    delete _pendingIQs[iq.id];
                }
                else {
					var exts:Array = iq.getAllExtensions();
					for (var ns:String in exts) {
						// Static type casting
						var ext:IExtension = exts[ns] as IExtension;
						if (ext != null) {
							var event:IQEvent = new IQEvent(ext.getNS());
							event.data = ext;
							event.iq = iq;
							dispatchEvent( event );
						}
					}
                }
            }
            return iq;
        }
        
        
        
        //--------------------------------------
        //  Events > Handlers
        //--------------------------------------
        private function onKeepAliveTimer(evt:Event) : void {
            Logger.debug("XMPPConnection::onKeepAliveTimer() " );
            sendKeepAlive();
            resetKeepAliveTimer();
        }

        private function resetKeepAliveTimer() : void {
            if(_keepAliveTimer)
            {
                _keepAliveTimer.reset();
            }else{
	            _keepAliveTimer = new Timer(300000);
	            _keepAliveTimer.addEventListener(TimerEvent.TIMER, onKeepAliveTimer);            	            	
            }
            _keepAliveTimer.start();
        }
        
        override protected function socketConnected(ev:Event):void{
        	super.socketConnected(ev);
            Logger.debug("XMPPConnection::onSocketConnected()" );
            dispatchEvent( new ConnectionSuccessEvent() );
            resetKeepAliveTimer();
        }

		//TODO integrate with super.bSocketReceivedData
        override protected function bSocketReceivedData( ev:SocketDataEvent ):void{
            var rawXML:String = _incompleteRawXML + ev.data as String;
            
            // Logger.debug('RAW XML: ' + rawXML);
            
            if (containsClosedStreamTag(rawXML)){
                // TODO: Check for <stream:error> if duplicate login
                // - If dup login, pass error string to disconnect()
                // - Error string should propagate to container, which should recognize it and change to a user-friendly explanation
                /*
                <stream:error>
                    <conflict xmlns='urn:ietf:params:xml:ns:xmpp-streams'/>
                    <text xml:lang='' xmlns='urn:ietf:params:xml:ns:xmpp-streams'>Replaced by new connection</text>
                </stream:error>
                */
                Logger.debug('Received closed stream tag from server: '+rawXML);
                disconnect();
                return;
            }
            
            if (containsOpenStreamTag(rawXML)){
                rawXML = rawXML.concat("</stream:stream>");
            }

            var xmlData:XMLDocument = stringToXML(rawXML,ev);
            
            if (xmlData == null){
                return;
            }
            
            for (var i:int = 0; i < xmlData.childNodes.length; i++)
            {
                var node:XMLNode = xmlData.childNodes[i];
                Logger.debug("... handling " + node.nodeName);
                switch (node.nodeName.toLowerCase()){
                    case "stream:stream":
                        handleStreamStart(node);
                        break;
                    case 'stream:error':
                        handleStreamError(node);
                        break;
                    case "challenge":
                        handleChallenge(node);
                        break;
                    case "success":
                        handleSuccess();
                        break;
                    case "failure":
                        handleFailure(node);
                        break;
                    case "iq":
                        handleIQ(node);
                        break;
                    case "stream:features":
                        handleFeatures(node);
                        break;
                    case "message":
                        handleMessage(node);
                        break;
                    case 'presence':
                        handlePresence(node);
                        break;
                    default:
                        break;
                        
                }
            }
            
            
            
        }
        
        override protected function socketClosed(e:Event):void{
        	/*super.disconnect() has done
        	* var event:DisconnectionEvent = new DisconnectionEvent();
			*  dispatchEvent(event);
			* it doesn't need to super.socketClosed() here
        	*/
            Logger.debug("XMPPConnection::onSocketClosed()" );
            disconnect();
        }
        
        override protected function onIOError(event:IOErrorEvent):void
        {
            Logger.debug("XMPPConnection::onIOError() : " + event.text);
            super.onIOError(event);
            dispatchEvent(event);
        }
        
        override protected function securityError(event:SecurityErrorEvent):void
        {
        	super.securityError(event);
            Logger.debug("There was a security error of type: " + event.type + "\nError: " + event.text);
            active = false;
            loggedIn = false;            
            dispatchEvent(event);
        }
        
        
        //--------------------------------------
        //  Internal helpers
        //--------------------------------------        
        
        private function stringToXML(rawXML:String, ev:SocketDataEvent) : XMLDocument {
            var xmlData:XMLDocument = new XMLDocument();
            xmlData.ignoreWhite = true;
            try {
                Logger.debug('... trying to parse: ' + rawXML);
                xmlData.parseXML(rawXML);
                _incompleteRawXML = '';
            } catch (e:Error) {
                _incompleteRawXML += ev.data as String;
                return null;
            }
            return xmlData;
        }
        
        
        private function containsOpenStreamTag(xml:String) : Boolean {
            var openStreamRegex:RegExp = new RegExp("<stream:stream");
            var resultObj:Object = openStreamRegex.exec(xml);
            return (resultObj != null);
        }
        
        private function containsClosedStreamTag(xml:String) : Boolean {
            var closeStreamRegex:RegExp = new RegExp("<\/stream:stream");
            var resultObj:Object = closeStreamRegex.exec(xml);
            return (resultObj != null);
        }


        
        protected function openStreamTag() : String {
            return "<?xml version=\"1.0\"?><stream:stream to=\"" + server + 
                "\" xmlns=\"jabber:client\" xmlns:stream=\"http://etherx.jabber.org/streams\" version=\"1.0\">";
        }
        
        protected function closeStreamTag() : String {
            return "</stream:stream>";
        }
        
    } 
}
