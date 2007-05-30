/*
Adobe Systems Incorporated(r) Source Code License Agreement
Copyright(c) 2005 Adobe Systems Incorporated. All rights reserved.
	
Please read this Source Code License Agreement carefully before using
the source code.
	
Adobe Systems Incorporated grants to you a perpetual, worldwide, non-exclusive,
no-charge, royalty-free, irrevocable copyright license, to reproduce,
prepare derivative works of, publicly display, publicly perform, and
distribute this source code and such derivative works in source or
object code form without any attribution requirements.
	
The name "Adobe Systems Incorporated" must not be used to endorse or promote products
derived from the source code without prior written permission.
	
You agree to indemnify, hold harmless and defend Adobe Systems Incorporated from and
against any loss, damage, claims or lawsuits, including attorney's
fees that arise or result from your use or distribution of the source
code.
	
THIS SOURCE CODE IS PROVIDED "AS IS" AND "WITH ALL FAULTS", WITHOUT
ANY TECHNICAL SUPPORT OR ANY EXPRESSED OR IMPLIED WARRANTIES, INCLUDING,
BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE ARE DISCLAIMED. ALSO, THERE IS NO WARRANTY OF
NON-INFRINGEMENT, TITLE OR QUIET ENJOYMENT. IN NO EVENT SHALL MACROMEDIA
OR ITS SUPPLIERS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOURCE CODE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
package com.adobe.webapis.awss3
{
	import flash.net.URLLoaderDataFormat;
	import flash.net.URLRequest;
	import flash.net.URLLoader;
	import flash.net.URLStream;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.EventDispatcher;
	import flash.net.URLRequestHeader;
	import com.adobe.utils.DateUtil;
	import flash.utils.ByteArray;
	import flash.events.ProgressEvent;
	import flash.net.FileReference;
	import com.hurlant.crypto.hash.SHA1;
	import com.hurlant.crypto.hash.HMAC;
	import com.hurlant.crypto.hash.MD5;
	import com.hurlant.util.Base64;
	import flash.events.HTTPStatusEvent;
	import mx.formatters.DateFormatter;
	import flash.filesystem.File;
	import flash.events.DataEvent;

	[Event(name="error",           type="com.adobe.aws.AWSS3Event")]
	[Event(name="listBuckets",     type="com.adobe.aws.AWSS3Event")]
	[Event(name="listObjects",     type="com.adobe.aws.AWSS3Event")]
	[Event(name="bucketCreated",   type="com.adobe.aws.AWSS3Event")]
	[Event(name="bucketDeleted",   type="com.adobe.aws.AWSS3Event")]
	[Event(name="objectDeleted",   type="com.adobe.aws.AWSS3Event")]
	[Event(name="objectSaved",     type="com.adobe.aws.AWSS3Event")]
	[Event(name="objectRetrieved", type="com.adobe.aws.AWSS3Event")]
	[Event(name="progress",        type="flash.events.ProgressEvent")]

	public class AWSS3
		extends EventDispatcher
	{
		public var accessKey:String;
		public var secretAccessKey:String;
		public var secretAccessKeyBytes:ByteArray;
		private var dateFormatter:DateFormatter;
		private var s3ns:Namespace = new Namespace("http://s3.amazonaws.com/doc/2006-03-01/");
		private static const AMAZON_ENDPOINT:String = "s3.amazonaws.com";
		private var hmac:HMAC;
		private var md5:MD5;

		public function AWSS3(accessKey:String, secretAccessKey:String)
		{
			this.accessKey = accessKey;
			this.secretAccessKey = secretAccessKey;
			this.secretAccessKeyBytes = new ByteArray();
			this.secretAccessKeyBytes.writeUTFBytes(this.secretAccessKey);

			// Set up the date formatter
			dateFormatter = new DateFormatter();
			dateFormatter.formatString = "EEE, D MMM YYYY J:NN:SS";
			
			// Hash and encryption tools
			md5 = new MD5();
			hmac = new HMAC(new com.hurlant.crypto.hash.SHA1());
		}
		
		public function setCredentials(accessKey:String, secretAccessKey:String):void
		{
			this.accessKey = accessKey;
			this.secretAccessKey = secretAccessKey;
		}
		
		public function listBuckets():void
		{
			var stream:URLStream = getURLStream();
			stream.addEventListener(Event.COMPLETE,
				function(e:Event):void
				{
					var buckets:Array = new Array();
					var bucketXML:XML = XML(getDataFromStream(stream));
					for each (var b:XML in bucketXML..s3ns::Bucket)
					{
						var newBucket:Bucket = new Bucket();
						newBucket.name = b.s3ns::Name;
						newBucket.creationDate = DateUtil.parseW3CDTF(b.s3ns::CreationDate);
						buckets.push(newBucket);
					}
					var ae:AWSS3Event = new AWSS3Event(AWSS3Event.LIST_BUCKETS);
					ae.data = buckets;
					dispatchEvent(ae);
				});
			var req:URLRequest = getURLRequest("GET", "/");			
			stream.load(req);			
		}

		public function listObjects(bucketName:String,
									prefix:String = null,
									marker:String = null,
									maxKeys:int = -1):void
		{
			var stream:URLStream = getURLStream();
			stream.addEventListener(Event.COMPLETE,
				function(e:Event):void
				{
					var objects:Array = new Array();
					var objectXML:XML = XML(getDataFromStream(stream));
					for each (var o:XML in objectXML..s3ns::Contents)
					{
						var newObject:S3Object = new S3Object();
						newObject.key = o.s3ns::Key;
						newObject.lastModified = DateUtil.parseW3CDTF(o.s3ns::LastModified);
						newObject.size = Number(o.s3ns::Size);
						objects.push(newObject);
					}
					var ae:AWSS3Event = new AWSS3Event(AWSS3Event.LIST_OBJECTS);
					ae.data = objects;
					dispatchEvent(ae);
				});
			if (prefix != null) bucketName += "";
			var req:URLRequest = getURLRequest("GET", "/" + escape(bucketName));			
			stream.load(req);			
		}

		public function createNewBucket(bucketName:String):void
		{
			var stream:URLStream = getURLStream();
			stream.addEventListener(HTTPStatusEvent.HTTP_STATUS,
				function(e:HTTPStatusEvent):void
				{
					var ae:AWSS3Event;
					if (e.status == 200)
					{
						ae = new AWSS3Event(AWSS3Event.BUCKET_CREATED);
						dispatchEvent(ae);
					}
					else if (e.status == 409)
					{
						ae = new AWSS3Event(AWSS3Event.ERROR);
						ae.data = "This bucket name is not unique. Bucket names must be unique across all of S3.";
						dispatchEvent(ae);
					}
					else
					{
						ae = new AWSS3Event(AWSS3Event.ERROR);
						dispatchEvent(ae);						
					}
				});
			var req:URLRequest = getURLRequest("PUT", "/" + escape(bucketName));			
			stream.load(req);			
		}

		public function deleteBucket(bucketName:String):void
		{
			var stream:URLStream = getURLStream();
			stream.addEventListener(HTTPStatusEvent.HTTP_STATUS,
				function(e:HTTPStatusEvent):void
				{
					var ae:AWSS3Event;
					if (e.status == 204)
					{
						ae = new AWSS3Event(AWSS3Event.BUCKET_DELETED);
						dispatchEvent(ae);
					}
					else if (e.status == 409)
					{
						ae = new AWSS3Event(AWSS3Event.ERROR);
						ae.data = "Only empty buckets can be deleted.";
						dispatchEvent(ae);
					}
					else
					{
						ae = new AWSS3Event(AWSS3Event.ERROR);
						dispatchEvent(ae);						
					}
				});
			var req:URLRequest = getURLRequest("DELETE", "/" + escape(bucketName));			
			stream.load(req);			
		}

		public function deleteObject(bucketName:String, objectName:String):void
		{
			var stream:URLStream = getURLStream();
			stream.addEventListener(HTTPStatusEvent.HTTP_STATUS,
				function(e:HTTPStatusEvent):void
				{
					var ae:AWSS3Event;
					if (e.status == 204)
					{
						ae = new AWSS3Event(AWSS3Event.OBJECT_DELETED);
						dispatchEvent(ae);
					}
					else
					{
						ae = new AWSS3Event(AWSS3Event.ERROR);
						dispatchEvent(ae);						
					}
				});
			var req:URLRequest = getURLRequest("DELETE", "/" + escape(bucketName) + "/" + escape(objectName));
			stream.load(req);			
		}

		public function saveObject(bucketName:String, objectName:String, contentType:String, objectFile:File):void
		{
			trace(objectFile.toString());
			objectFile.addEventListener(ProgressEvent.PROGRESS,
				function (e:ProgressEvent):void
				{
					dispatchEvent(e);
				});
			objectFile.addEventListener(Event.COMPLETE,
				function(e:Event):void
				{
					var ae:AWSS3Event = new AWSS3Event(AWSS3Event.OBJECT_SAVED);
					dispatchEvent(ae);
				});

			objectFile.addEventListener(IOErrorEvent.IO_ERROR, onError);
			var req:URLRequest = getURLRequest("PUT", "/" + escape(bucketName) + "/" + escape(objectName), contentType);
			if (contentType != null) req.requestHeaders.push(new URLRequestHeader("Content-Type", contentType));
			objectFile.upload(req);
		}

		public function getObject(bucketName:String, objectName:String):void
		{
			var stream:URLStream = getURLStream();
			var contentType:String;
			stream.addEventListener(ProgressEvent.PROGRESS,
				function (e:ProgressEvent):void
				{
					dispatchEvent(e);
				});
			stream.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS,
				function(e:HTTPStatusEvent):void
				{
					if (e.status != 200)
					{
						var ae:AWSS3Event;
						ae = new AWSS3Event(AWSS3Event.ERROR);
						dispatchEvent(ae);
					}
					for each (var h:URLRequestHeader in e.responseHeaders)
					{
						// Can get other headers like ETag and Content-Length to add to the S3Object...
						if (h.name.toLocaleLowerCase() == "content-type") { contentType = h.value; break; };
					}
				});
			stream.addEventListener(Event.COMPLETE,
				function(e:Event):void
				{
					var aee:AWSS3Event;
					aee = new AWSS3Event(AWSS3Event.OBJECT_RETRIEVED);
					var obj:S3Object = new S3Object();
					obj.bucket = bucketName;
					obj.key = objectName;
					obj.bytes = getDataFromStream(stream);
					obj.type = contentType;
					aee.data = obj;
					dispatchEvent(aee);
				});
			var req:URLRequest = getURLRequest("GET", "/" + escape(bucketName) + "/" + escape(objectName));
			stream.load(req);			
		}

		public function getTemporaryObjectURL(bucketName:String, objectName:String, timeValue:Number, secure:Boolean = true):String
		{
			var ms:Number = new Date().valueOf();
			var s:Number = Math.round(ms / 1000);
			s += timeValue;
			var authString:String = getAuthenticationString("GET", String(s), "/" + escape(bucketName) + "/" + escape(objectName));
			var url:String = (secure) ? "https" : "http";
			url += "://" + AMAZON_ENDPOINT + "/" + escape(bucketName) + "/" + escape(objectName) + "?AWSAccessKeyId="+this.accessKey+"&Expires="+s+"&Signature="+authString;
			return url;
		}

		// Private functions

		private function getURLStream():URLStream
		{
			var stream:URLStream = new URLStream();
			stream.addEventListener(IOErrorEvent.IO_ERROR, onError);
			return stream;
		}

		private function getDataFromStream(stream:URLStream):ByteArray
		{
			var bytes:ByteArray = new ByteArray();
			stream.readBytes(bytes);
			return bytes;
		}

		private function getURLRequest(method:String, resource:String, contentType:String = null, hash:String = null, secure:Boolean = true):URLRequest
		{
			var protocol:String = (secure) ? "https" : "http";
			var req:URLRequest = new URLRequest(protocol + "://" + AMAZON_ENDPOINT + resource);
			req.shouldCacheResponse = false;
			req.useCache = false;
			req.method = method;
			var dateString:String = getDateString(new Date());
			var dateHeader:URLRequestHeader = new URLRequestHeader("Date", dateString);
			var authHeader:URLRequestHeader = new URLRequestHeader("Authorization", getAuthenticationHeader(method, dateString, resource, contentType, hash));
			req.requestHeaders.push(dateHeader);
			req.requestHeaders.push(authHeader);
			return req;
		}

		private function onError(e:IOErrorEvent):void
		{
			dispatchEvent(e);
		}

		private function getDateString(d:Date):String
		{
			var dd:Date = new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds(), d.getUTCMilliseconds());
			var ds:String = dateFormatter.format(dd);
			return ds + " GMT";
		}
				
		private function getAuthenticationHeader(verb:String,
												 dateString:String,
												 resource:String,
												 contentType:String = null,
												 hash:String = null):String
		{
			return ("AWS " + this.accessKey + ":" + getAuthenticationString(verb, dateString, resource, contentType, hash));
		}

		private function getAuthenticationString(verb:String,
												 dateString:String,
												 resource:String,
												 contentType:String = null,
												 hash:String = null):String
		{
			var toSign:String = verb + "\n";
			toSign += (hash != null) ? hash + "\n" : "\n";
			toSign += (contentType != null) ? contentType + "\n" : "\n";
			toSign += dateString + "\n" + resource;
			var toSignBytes:ByteArray = new ByteArray();
			toSignBytes.writeUTFBytes(toSign);			
			var hmacBytes:ByteArray = hmac.compute(secretAccessKeyBytes,toSignBytes);
			return Base64.encodeByteArray(hmacBytes);
		}
		
		private function zeroPad(n:Number):String
		{
			return (n < 10) ? String("0"+n) : String(n);
		}
	}
}