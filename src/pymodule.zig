const std = @import("std");
const builtin = @import("builtin");
const python = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("Python.h");
});

const TypeInfo = std.builtin.TypeInfo;

pub const PyObject = struct {
    ref: Ptr,

    const Ptr = [*c]python.PyObject;
    const Self = @This();

    const nullptr = Self{ .ref = null };

    fn new(r: Ptr) Self {
        return Self{ .ref = r };
    }

    pub fn parseTuple(self: Self, comptime T: type) ?T {
        const info = @typeInfo(T);
        if (info != .Struct)
            @compileError("parseTuple expects a struct type");

        const fields = info.Struct.fields;
        comptime var argsFieldList: [fields.len + 2]TypeInfo.StructField = undefined;
        // TODO: Some types will need to be unpacked into an intermediate variable (e.g. bool -> c_int)
        // TODO: Some types require multiple characters
        comptime var fmt: [fields.len + 1]u8 = undefined;
        comptime {
            // Input PyObject to parse
            argsFieldList[0] = TypeInfo.StructField{
                .name = "0",
                .field_type = Ptr,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf([*c]u8),
            };
            // Format string
            argsFieldList[1] = TypeInfo.StructField{
                .name = "1",
                .field_type = [*c]const u8,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf([*c]u8),
            };
            fmt[fields.len] = 0;
            inline for (fields) |field, i| {
                switch (field.field_type) {
                    // TODO: Map standard Zig Int types to c_* types used by Python
                    u8 => fmt[i] = 'B',
                    f32 => fmt[i] = 'f',
                    f64 => fmt[i] = 'd',
                    else => @compileError("Unhandled type" ++ field),
                }
                var numBuf: [8]u8 = undefined;
                argsFieldList[i + 2] = TypeInfo.StructField{
                    .name = std.fmt.bufPrint(&numBuf, "{d}", .{i + 2}) catch unreachable,
                    .field_type = CPointer(field.field_type),
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf([*c]u8),
                };
            }
        }
        const Args = @Type(TypeInfo{
            .Struct = TypeInfo.Struct{
                .is_tuple = true,
                .layout = .Auto,
                .decls = &[_]std.builtin.TypeInfo.Declaration{},
                .fields = &argsFieldList,
            },
        });

        var args: Args = undefined;
        args[0] = self.ref;
        args[1] = &fmt[0];
        var result: T = undefined;
        inline for (fields) |field, i| {
            args[i + 2] = &@field(result, field.name);
        }
        if (@call(.{}, python.PyArg_ParseTuple, args) == 0) {
            return null;
        }
        return result;
    }

    pub fn parse(self: Self, comptime T: type) ?T {
        const TupleT = std.meta.Tuple(&[_]type{T});
        return if (self.parseTuple(TupleT)) |tuple| tuple[0] else null;
    }

    pub fn build(value: anytype) Self {
        const info = @typeInfo(@TypeOf(value));
        const args = switch (@TypeOf(value)) {
            u8 => .{ "b", value },
            f32 => .{ "f", value },
            f64 => .{ "d", value },
            void => .{""},
            else => @compileError("unhandled type" ++ @Type(value)),
        };
        return if (@call(.{}, python.Py_BuildValue, args)) |o| Self.new(o) else Self.nullptr;
    }
};

fn CPointer(comptime T: type) type {
    return @Type(TypeInfo{ .Pointer = TypeInfo.Pointer{
        .size = .C,
        .is_const = false,
        .is_volatile = false,
        .alignment = @alignOf(T),
        .child = T,
        .is_allowzero = true,
        .sentinel = null,
    } });
}

fn makeMethod(comptime Module: anytype, comptime decl: TypeInfo.Declaration) ?python.PyMethodDef {
    if (!decl.is_pub or decl.data != .Fn)
        return null;

    const fnDecl = decl.data.Fn;
    if (fnDecl.is_var_args)
        return null;

    const ArgsTuple = std.meta.ArgsTuple(fnDecl.fn_type);
    const fnInfo = @typeInfo(fnDecl.fn_type);
    if (fnInfo != .Fn or fnInfo.Fn.is_generic)
        return null;

    const fnWrapper = struct {
        fn f(self: PyObject.Ptr, args: PyObject.Ptr) callconv(.C) PyObject.Ptr {
            const fnArgs = PyObject.new(args).parseTuple(ArgsTuple);
            if (fnArgs == null) {
                python.PyErr_SetString(python.PyExc_ValueError, "Incorrect function argument types/arity");
                return null;
            }

            const ret = @call(.{}, @field(Module, decl.name), fnArgs.?);
            return PyObject.build(ret).ref;
        }
    }.f;

    return python.PyMethodDef{
        .ml_name = &decl.name[0],
        .ml_meth = fnWrapper,
        .ml_flags = python.METH_VARARGS,
        // TODO: Generate docstring with argument types
        .ml_doc = null,
    };
}

pub fn createModule(comptime name: []const u8, comptime Module: anytype) void {
    const moduleDecls = std.meta.declarations(Module);

    var i = 0;
    var pyMethods = [1]python.PyMethodDef{.{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null }} ** (moduleDecls.len + 1);
    inline for (moduleDecls) |decl| {
        if (makeMethod(Module, decl)) |m| {
            pyMethods[i] = m;
            i += 1;
        }
    }

    var pyModule = python.PyModuleDef{
        .m_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = null,
            },
            .m_init = null,
            .m_index = 0,
            .m_copy = null,
        },
        .m_name = &name[0],
        .m_doc = null,
        .m_size = -1,
        .m_methods = &pyMethods[0],
        .m_slots = null,
        .m_traverse = null,
        .m_clear = null,
        .m_free = null,
    };

    const initFn = struct {
        fn f() callconv(.C) [*c]python.PyObject {
            // Leak this copy of `pyModule`
            // It would be much nicer if this could go in the .data section?
            var mod_unconst = std.heap.page_allocator.dupe(python.PyModuleDef, &[_]python.PyModuleDef{pyModule}) catch |e| @panic("failed to allocate");
            return python.PyModule_Create(&mod_unconst[0]);
        }
    }.f;

    @export(initFn, .{ .name = "PyInit_" ++ name, .linkage = .Strong });
}
