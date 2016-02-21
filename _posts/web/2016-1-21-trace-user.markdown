---
layout: "post"
title: "使用ETag跟踪用户"
date: "2016-1-21 18:05"
categories:  ["web", "nginx"]
---

工作的时候总感觉静不下来总结，假期里终于可以好好整理总结了。前不久，针对更加准确得获得用户uv, 做了一些优化工作, 期间收获颇多。这篇我会总结新闻网站跟踪用户的方法，另外还将有一篇介绍用户唯一id生成方法的。

#### 新闻网站跟踪用户的方法

如果你的网站用户总是处于登录状态，那么就没有这烦恼了，每次访问都会携带user_id, 不管
用户清cookies、清cache、换浏览器、换手机， 用户只要登陆，都可以继跟踪到用户。

但是对于新闻类网站，用户几乎没有登录的。怎样跟踪用户呢？我们原先有如下两种方法：

1. 后端生成用户id, 存到cookie里，只要用户cookie不清，下次访问就能从cookie里得到用户的id。此方法要求浏览器支持cookie, 用户清cookie后，跟踪终止。
2. 对于那些不支持cookie的低端手机或者关闭了cookie功能的手机，我们把生成的user_id渲染到页面上每条链接的参数里， 这样用户继续点击链接时，通过链接参数，也能跟踪到用户。但是，只要用户关闭了网页，重新打开页面就被识别为了新用户

上边两种方法统计到的用户，都不能保证这些用户真正看到了页面，比如由于网络原因， 数据没有传送到用户端，那么这次的统计是无意义的，还有些爬虫，没有别统计系统过滤掉，它们的访问也产生了uv。我们想获得的是能够使页面曝光的用户uv。

所以优化任务有两点：

1. 提高统计uv的健壮性。 用户清cookie, 关闭页面等行为不再影响uv
2. 提高统计的真实性。 只有当页面曝光后，才算一次uv

#### 使用ETags存储用户id

我参考了[http://lucb1e.com/rp/cookielesscookies/](http://lucb1e.com/rp/cookielesscookies/) 这篇博文中的方法, 核心是是用ETags存储user_id, Http ETags的知识参考：[https://en.wikipedia.org/wiki/HTTP_ETag](https://en.wikipedia.org/wiki/HTTP_ETag)， 讲得非常详细。

因为cache是所有浏览器都支持的，所以ETags的方法对于那些不支持cookie的手机是种补充； 把user_id既存在cache，也存在cookie里，
健壮性也可提高； 通过图片请求统计uv, 可保证真实性。

#### 实施方案

在页面中加入一张1x1像素的小图，第一次访问小图时，服务器端生成user_id, 把user_id作为图片的ETags返回。 浏览器缓存图片和图片的ETags值，当再有页面访问时，也就有有这张小图的访问。如果缓存没过期的话（需要把过期时间设置得足够大）， 浏览器会先发送
包含if-none-match头的请求，去验证图片是否修改过，如果没变，服务器端返回304, 浏览器使用缓存图片，如果图片改变了
服务器返回200和图片内容。 if-none-match的值就是第一次访问传递的ETags, 即用户的id。

生成user_id的方法： 先检查cookie里是否有user_id, 如果有则使用cookie. 否则使用第三方模块生成uuid, 模块的github地址为[https://github.com/cybozu/nginx-uuid4-module](https://github.com/cybozu/nginx-uuid4-module)， 这个在下一篇博客分析。

对于这张小图的访问逻辑都写在nginx配置里了，如下：


    location /msohu_uv.gif {
        uuid4 $etag;
        set $condition 0;

        if ($http_if_none_match ~ ^[-a-zA-Z0-9]+$) {
            set $condition 1;
            return 304;
        }

        if ($cookie__smuid ~ ^[a-zA-Z0-9]+$) {
            set $condition 2;
            add_header ETag $cookie__smuid;
        }

        if ($condition = 0) {
            add_header ETag $etag;
        }
        empty_gif;
    }

关于nginx配置中if的使用参考：[http://agentzh.blogspot.com/2011/03/how-nginx-location-if-works.html](http://agentzh.blogspot.com/2011/03/how-nginx-location-if-works.html)
