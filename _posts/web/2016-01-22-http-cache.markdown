---
layout: "post"
title: "HTTP缓存 1.0 vs 1.1"
date: "2016-1-22 18:05"
categories:  ["web", "http"]
---

在“[使用ETag跟踪用户](/web/nginx/2016/01/21/trace-user)”中有一点被忽略了，因为要用这张小图统计统计uv, 所以要求浏览器必须每次都要发送这个图片的请求。这需要服务器对图片的缓存策略做设置。

http/1.0 和 http/1.1 的缓存策略不同，浏览器缓存这事看似简单，实际上很容易模棱两可，造成疏忽。

#### HTTP/1.0

协议文档： [https://www.w3.org/Protocols/HTTP/1.0/spec.html](https://www.w3.org/Protocols/HTTP/1.0/spec.html)

相关字段：

* Date: 服务器响应的时间
* Expires: 资源过期时间
* Last-Modified: 资源最后修改时间
* If-Modified-Since: 用来验证资源是否过期

策略：

如果Expires设置的时间在Date之后，则浏览器在Expires标记的时间之前都不会访问服务器了，而是使用浏览器缓存，入下图：

![](/assets/pic/2016/02/http1.0cache1.png)

如果Expires设置的时间在Date之前，或者浏览器时间已经在Expires之后，那么再次访问图片时， 浏览器就要向服务器发送请求，但不是重新拉取数据，而是询问服务器该资源是否过期，方法时，把上次response中Last-Modified的时间作为If-Modified-Since的时间，发送请求，服务器对比该时间和资源目前的更改时间，如果未更改，则返回304，否则传输新文件，如下：

![](/assets/pic/2016/02/http-1.0-cache2.png)

#### HTTP/1.1

HTTP/1.0缓存机制完全依赖时间，弊端显而易见，服务器、客户端的时钟不同步，文档的
更新周期小于1s, 都会出现问题。

所以HTTP/1.1提倡的缓存机制是，对比文档的hash值，文档内容变，则hash变，用相对时间代替绝对时间

协议文档：[https://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html](https://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html)

HTTP/1.1 继承 HTTP/1.0 所以HTTP/1.0的相关字段仍然有效，保留的这些字段就是为了兼容那些仅支持HTTP/1.0的客户端。 HTTP/1.1服务器不应该设置与1.0矛盾的过期策略, 1.1的服务器在没有文档hash值时，也可以使用If-Modified-Since进行判断文档过期。

新增字段：

* Cache-Control: 用来控制浏览器的缓存行为，详见[https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.9](https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.9)
* ETag: 文档的Hash值
* If-None-Match: 用来验证资源是否过期，即文档Hash值是否变化

Cache-Control最容易理解也是最常用的就是：

* no-cache: 浏览器缓存，但是认为是过期缓存
* no-store: 浏览器不缓存
* max-age：缓存有效时间段

如果想要浏览器每次发送请求，还启用缓存，那就使用`Cache-Control: no-cache`, 每次访问图片，浏览器都会去验证Etag.  过程如下：

![](/assets/pic/2016/02/http1.1-cache.png)

#### Nginx设置

最好的方法就是使用`expires`指令， 它兼顾1.1和1.0，  即所有的字段都会给设置。但是nginx不支持ETag, 需要自己实现。
如果`expires -1`, 就是我需要的，浏览器既缓存数据，但是每次访问都请求服务器。
详见： [http://nginx.org/en/docs/http/ngx_http_headers_module.html](http://nginx.org/en/docs/http/ngx_http_headers_module.html)
