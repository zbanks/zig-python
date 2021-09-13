`zig-python`
============

Automatically generate native Python extension modules from Zig libraries.

This is primarily a **proof-of-concept** of Zig's compile-time metaprogramming, rather than being practical.
In retrospect, it would be much simpler to run at *build* time instead of `comptime`, like [`zig-header-gen`](https://github.com/suirad/zig-header-gen) is doing.

Also, there's probably a good reason that more mature libraries for other languages like [PyO3](https://github.com/PyO3/pyo3) are significantly less "automagic" than I've been here.

Running the Example
-------------------

The library is currently hardcoded to use Python 3.9.

```
zig build
ln -s zig-out/lib/libpymodule.so example_zig.so
python3.9 -c "import example_zig as ex; ex.hello(); print(ex.add(1, 2)); print(ex.mul(2, 3, 4))"
python3.9 -c "import example_zig as ex; print(ex.__name__, dir(ex))"
```

Expected output:

```
Hello, world!
add: a=1, b=2
3
24.0
example_zig ['__doc__', '__file__', '__loader__', '__name__', '__package__', '__spec__', 'add', 'hello', 'mul']
```
