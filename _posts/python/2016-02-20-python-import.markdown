---
layout: "post"
title: "python非侵入式代码监控(一): python import hook"
date: "2016-02-20 17:18"
categories: ['python']
---

[Tornado_debug](https://github.com/shaolianbo/tornado_debug)是我写的一个非侵入式Tornado性能监控项目。 计划用两篇blog总结其核心技术。 这是第一篇，总结python模块钩子的原理与python环境自定义出事化的方法。另一篇用来介绍tornado_debug本身的架构。

tornado_debug首先要解决的问题是，开发一个agent, 使用agent启动python程序，并能对python程序中导入的模块自动添加装饰器，用来统计性能数据。

解决方案是： agent修改PYTHONPATH,  启动python子进程， site模块初始化过程中添加import hook.

核心的技术如下：

#### 什么是import hook?

每当导入模块的时候，触发的操作就是import hook。比如如果一个web项目中使用了redis操作， 想要统计在一次会话中redis的执行次数与时间, 这时， 就可以针对[redis客户端](https://pypi.python.org/pypi/redis)设置hook, 当项目代码中导入redis时， 对每个redis操作函数添加装饰器，比如`get`, 项目中的每次get操作就都能统计到了。

#### python import hook原理

python在查找模块时，有三个层次, 先后为：

1. cache, 即 `sys.modules`
2. import hook
3. 常规的导入

新导入的模块的都会放到`sys.modules`中。

hook执行导入模块涉及两个类：

1. finder: 必须有的方法`finder.find_module(fullname, path=None)`, 作用是查找模块，返回一个loader
2. loader: 必须有的方法`loader.load_module(fullname)`, 作用是加载模块

其中，import hook又有两个层次：

1. `sys.meta_path`, 这是一个列表，每个元素都是一个finder实例。 导入模块时，遍历finder列表，调用finder.find_module, 直到有一个finder返回一个loader, 然后调用loader的load_module方法，加载模块。 否则进入下一层。
2. `sys.path_hooks`, 同样也是一个finder类(不是finder实例)的列表，sys.path 中的每一个路径会按顺序输入sys.path_hooks中的每个Finder的init函数, 直到某个finder没有抛出ImportError，则该模块的导入会交给这个finder执行。同样finder会返回loader, 去执行加载。

一旦finder被选中，不管模块能否加载成功，模块导入的流程都不会进入下一层。

`sys.path_hooks` 中的 hook，只有在导入顶层模块时才调用, 比如： `import test`会使用这path_hooks, `import test.world`就不会。 `sys.meta_path`就没有这个限制。

python2.7的import hook, 详见文档： [https://www.python.org/dev/peps/pep-0302/](https://www.python.org/dev/peps/pep-0302/)

测试代码如下：

    # coding: utf8
    import sys
    import imp


    class PATHImportLoader(object):
        def is_package(self, fullname):
            return '.' not in fullname

        def load_module(self, fullname):
            # code = self.get_code(fullname)
            ispkg = self.is_package(fullname)
            mod = sys.modules.setdefault(fullname, imp.new_module(fullname))
            mod.__file__ = "<%s>" % self.__class__.__name__
            mod.__loader__ = self
            if ispkg:
                mod.__path__ = []
                mod.__package__ = fullname
            else:
                mod.__package__ = fullname.rpartition('.')[0]
            # exec(code, mod.__dict__)
            mod.word = "this is %s" % fullname
            print 'load "%s" success' % fullname
            return mod

    Class PATHImportFinder(object):

        PATH_TRIGGER = '/test'
        MODULES = ['hello', 'datetime']

        def __init__(self, path_entry):
            print "looking path"
            if path_entry != self.PATH_TRIGGER:
                print 'PATHImportFinder does not work for %s' % path_entry
                raise ImportError()
            return

        def find_module(self, fullname, path=None):
            print 'PATHImportFinder looking for "%s"' % fullname
            if fullname not in self.MODULES:
                print 'PATHImportFinder can not find module "%s"' % fullname
                raise ImportError()

            return PATHImportLoader()

    sys.path_hooks.append(PATHImportFinder)
    sys.path.insert(0, PATHImportFinder.PATH_TRIGGER)


    class METAImportLoader(PATHImportLoader):
        def load_module(self, fullname):
            mod = super(METAImportLoader, self).load_module(fullname)
            mod.word = mod.word.upper()
            return mod

    class METAImportFinder(object):
        def find_module(self, fullname, path=None):
            if fullname == 'hello' or  fullname.startswith('hello.'):
                print 'METAImportFinder is looking for "%s"' % fullname
                return METAImportLoader()

    sys.meta_path.append(METAImportFinder())

    import hello
    print hello.word
    import datetime
    print datetime.word
    import hello.test
    import datetime.test


#### site 模块： 用于python程序启动的时候，做一些自定义的处理

site — Site-specific configuration hook, 详见python文档：[https://docs.python.org/2/library/site.html](https://docs.python.org/2/library/site.html)

在python程序运行前，site模块会自动导入，并按照如下顺序完成初始化工作:

1. 将sys.prefix 、sys.exec_prefix 和 lib/pythonX.Y/site-packages 合成module的search path.。加入sys.path。eg: /home/jay/env/tornado/lib/python2.7/site-packages
2. 在添加的路径下寻找name.pth。 文件中描述了添加到sys.path的子文件夹路径。eg: 在我的/home/jay/env/tornado/lib/python2.7/site-packages下有一个newrelic.pth， 内容为"newrelic-2.46.0.37", 所以/home/jay/env/tornado/lib/python2.7/site-packages/newrelic-2.46.0.37/会被添加到sys.path。
3. `import sitecustomize` sitecustomize内部可以做任意的设置。
4. `import usercustomize` usercustomize 内部做任意的设置。 但是usercustomize习惯上放在user python path 下， eg: /home/jay/.local/lib/python2.7/site-packages.

所以可以设置特殊的usercustomize.py文件, 在python代码执行之前，添加import hook。
