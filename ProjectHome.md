This is an AS3 library for accessing Amazon's S3 service.  It only works in Apollo because of restrictions in the browser player.

It's pretty comprehensive.  It supports managing buckets and objects.  I haven't implemented some of the access control stuff yet, or the bucket listing pagination features.  These are trivial to add -- I just haven't found the time yet.  The hard part (the protocol) works perfectly, so adding functionality is pretty straightforward.

This library has the following dependencies:

As3Crypto (http://crypto.hurlant.com/)

as3corelib (http://code.google.com/p/as3corelib/)

The free Flex SDK (http://www.adobe.com/products/flex/sdk/)

There is currently no zip archive available.  Please check the code out using subversion.