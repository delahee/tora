/* ************************************************************************ */
/*																			*/
/*  Tora - Neko Application Server											*/
/*  Copyright (c)2008 Motion-Twin											*/
/*																			*/
/* This library is free software; you can redistribute it and/or			*/
/* modify it under the terms of the GNU Lesser General Public				*/
/* License as published by the Free Software Foundation; either				*/
/* version 2.1 of the License, or (at your option) any later version.		*/
/*																			*/
/* This library is distributed in the hope that it will be useful,			*/
/* but WITHOUT ANY WARRANTY; without even the implied warranty of			*/
/* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU		*/
/* Lesser General Public License or the LICENSE file for more details.		*/
/*																			*/
/* ************************************************************************ */
package tora;
import tora.Code;

class Protocol {

	var sock : #if sys sys.net.Socket #else flash.net.Socket #end;
	var headers : Array<{ key : String, value : String }>;
	var params : Array<{ key : String, value : String }>;
	var uri : String;
	var host : String;
	var port : Int;
	var lastMessage : Code;
	var dataLength : Int;
	#if sys
	var tmpOut : haxe.io.BytesOutput;
	#end

	static var CODES : Array<Code> = Lambda.array(Lambda.map(Type.getEnumConstructs(Code),callback(Reflect.field,Code)));

	public function new( url : String ) {
		headers = new Array();
		params = new Array();
		var r = ~/^http:\/\/([^\/:]+)(:[0-9]+)?(.*)$/;
		if( !r.match(url) )
			throw "Invalid url "+url;
		host = r.matched(1);
		var port = r.matched(2);
		uri = r.matched(3);
		if( uri == "" ) uri = "/";
		this.port = if( port == null ) 6667 else Std.parseInt(port.substr(1));
	}

	public function addHeader(key,value) {
		headers.push({ key : key, value : value });
	}

	public function addParameter(key,value) {
		params.push({ key : key, value : value });
	}

	public function reset() {
		headers = new Array();
		params = new Array();
	}

	public function call( url ) {
		if( sock == null ) {
			error("Not connected");
			return;
		}
		var r = ~/^http:\/\/([^\/:]+)(:[0-9]+)?(.*)$/;
		if( !r.match(url) )
			throw "Invalid url "+url;
		uri = r.matched(3);
		if( uri == "" ) uri = "/";
		onConnect(null);
	}
	
	public function poll() {
		#if sys
		try
		{
			sock.setBlocking(false);
			onSocketData(null);
		}
		catch(d:Dynamic)
		{
			
		}
		sock.setBlocking(true);
		#end
	}
	
	public function wait() {
		#if sys
		onSocketData(null);
		#end
	}

	public function connect() {
		#if flash
		sock = new flash.net.Socket();
		sock.addEventListener(flash.events.Event.CONNECT,onConnect);
		sock.addEventListener(flash.events.Event.CLOSE,onClose);
		sock.addEventListener(flash.events.IOErrorEvent.IO_ERROR, onClose);
        sock.addEventListener(flash.events.SecurityErrorEvent.SECURITY_ERROR, onClose);
		sock.addEventListener(flash.events.ProgressEvent.SOCKET_DATA,onSocketData);
		sock.connect(host,port);
		#elseif sys
		sock = new sys.net.Socket();
		var c = sock.connect(new sys.net.Host(host),port);
		#if neko sock.setFastSend(true); #end
		onConnect(null);
		trace('tora protocol connected');
		#end
	}

	public function close() {
		if( sock == null ) return;
		#if flash
		sock.removeEventListener(flash.events.Event.CLOSE,onClose);
		#end
		try sock.close() catch( e : Dynamic ) {};
		sock = null;
	}

	function send( code : Code, data : String ) {
		#if flash
		sock.writeByte(Type.enumIndex(code) + 1);
		var length = data.length;
		sock.writeByte(length & 0xFF);
		sock.writeByte((length >> 8) & 0xFF);
		sock.writeByte(length >> 16);
		sock.writeUTFBytes(data);
		#elseif sys
		var i = tmpOut;
		i.writeByte(Type.enumIndex(code) + 1);
		var length = data.length;
		i.writeByte(length & 0xFF);
		i.writeByte((length >> 8) & 0xFF);
		i.writeByte(length >> 16);
		i.writeString(data);
		#end
	}

	function onConnect(_) {
		if( sock == null ) return;
		#if sys
		tmpOut = new haxe.io.BytesOutput();
		#end
		send(CHostResolve,host);
		send(CUri,uri);
		for( h in headers ) {
			send(CHeaderKey,h.key);
			send(CHeaderValue,h.value);
		}
		var get = "";
		for( p in params ) {
			if( get != "" ) get += ";";
			get += StringTools.urlEncode(p.key)+"="+StringTools.urlEncode(p.value);
			send(CParamKey,p.key);
			send(CParamValue,p.value);
		}
		send(CGetParams,get);
		send(CExecute,"");
		#if flash
		sock.flush();
		#elseif sys
		var n = sock.write(tmpOut.getBytes().toString());
		tmpOut = null;
		trace( "tora protocol written:" + n);
		#end
	}

	function onSocketData(_) {
		while( true ) {
			if( sock == null ) return;
			#if flash
			if( lastMessage == null ) {
				if( sock.bytesAvailable < 4 ) return;
				var code = sock.readUnsignedByte() - 1;
				lastMessage = CODES[code];
				if( lastMessage == null ) {
					error("Unknown Code #"+code);
					return;
				}
				var d1 = sock.readUnsignedByte();
				var d2 = sock.readUnsignedByte();
				var d3 = sock.readUnsignedByte();
				dataLength = d1 | (d2 << 8) | (d3 << 16);
			}
			var bl : Int = sock.bytesAvailable;
			if( bl < dataLength )
				return;
			var bytes = new flash.utils.ByteArray();
			// ouch !! flash will read the whole data if 0 length !
			if( dataLength > 0 )
				sock.readBytes(bytes,0,dataLength);
			#elseif sys
			var i = sock.input;
			var code = i.readByte() - 1;
			lastMessage = CODES[code];
			if( lastMessage == null ) {
				error("Unknown Code #"+code);
				return;
			}
			var d1 = i.readByte();
			var d2 = i.readByte();
			var d3 = i.readByte();
			dataLength = d1 | (d2 << 8) | (d3 << 16);
			var bytes = i.read(dataLength);
			#end
			var msg = lastMessage;
			lastMessage = null;
			switch( msg ) {
			case CHeaderKey, CHeaderValue, CHeaderAddValue, CLog:
			case CPrint: onData(bytes.toString());
			case CError:
				error(bytes.toString());
				return;
			case CListen,CExecute:
				#if sys
				break;
				#end
			default:
				error("Can't handle "+msg);
				return;
			}
		}
	}

	function error( msg : String ) {
		try sock.close() catch( e : Dynamic ) {};
		sock = null;
		onError(msg);
	}

	#if flash
	function onClose( e : flash.events.Event ) {
		try sock.close() catch( e : Dynamic ) {};
		sock = null;
		onDisconnect();
	}
	#end

	public dynamic function onError( msg : String ) {
		throw msg;
	}

	public dynamic function onDisconnect() {
	}

	public dynamic function onData( data : String ) {
	}

}