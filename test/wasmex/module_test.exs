defmodule Wasmex.ModuleTest do
  use ExUnit.Case, async: true
  import TestHelper, only: [t: 1]

  doctest Wasmex.Module

  @wat """
  (module
    (type $add_one_t (func (param i32) (result i32)))
    (func $add_one_f (type $add_one_t) (param $value i32) (result i32)
      local.get $value
      i32.const 1
      i32.add)
    (export "add_one" (func $add_one_f)))
  """

  describe t(&Module.compile/2) <> " from WAT" do
    test "instantiates a simple module from wat" do
      {:ok, store} = Wasmex.Store.new()
      {:ok, module} = Wasmex.Module.compile(store, @wat)
      instance = start_supervised!({Wasmex, %{module: module, store: store}})
      assert {:ok, [42]} == Wasmex.call_function(instance, :add_one, [41])
    end

    test "errors when attempting to compile nonsense" do
      wat = "wat is this? not WAT for sure"
      {:ok, store} = Wasmex.Store.new()

      assert {:error,
              "Error while parsing bytes: expected `(`\n     --> <anon>:1:1\n      |\n    1 | wat is this? not WAT for sure\n      | ^."} ==
               Wasmex.Module.compile(store, wat)
    end
  end

  describe t(&Module.serialize/1) <> t(&Module.unsafe_deserialize/1) do
    test "a module can be serialized and deserialized again" do
      %{module: module} = TestHelper.wasm_module()
      {:ok, serialized} = Wasmex.Module.serialize(module)
      {:ok, deserialized_module} = Wasmex.Module.unsafe_deserialize(serialized)

      assert Wasmex.Module.exports(module) ==
               Wasmex.Module.exports(deserialized_module)
    end
  end

  describe t(&Module.name/1) do
    test "returns the module name" do
      {:ok, store} = Wasmex.Store.new()
      {:ok, module} = Wasmex.Module.compile(store, "(module $helloTest)")
      assert Wasmex.Module.name(module) == "helloTest"
    end

    test "returns nil for unnamed modules" do
      {:ok, store} = Wasmex.Store.new()
      {:ok, module} = Wasmex.Module.compile(store, @wat)
      assert Wasmex.Module.name(module) == nil
    end
  end

  describe t(&Module.exports/1) do
    test "lists exports of a module" do
      %{module: module} = TestHelper.wasm_module()

      expected = %{
        "__data_end" => {:global, %{mutability: :const, type: :i32}},
        "__heap_base" => {:global, %{mutability: :const, type: :i32}},
        "arity_0" => {:fn, [], [:i32]},
        "bool_casted_to_i32" => {:fn, [], [:i32]},
        "divide" => {:fn, [:i32, :i32], [:i32]},
        "endless_loop" => {:fn, [], []},
        "f32_f32" => {:fn, [:f32], [:f32]},
        "f64_f64" => {:fn, [:f64], [:f64]},
        "v128_v128" => {:fn, [:v128], [:v128]},
        "i32_i32" => {:fn, [:i32], [:i32]},
        "i32_i64_f32_f64_f64" => {:fn, [:i32, :i64, :f32, :f64], [:f64]},
        "i64_i64" => {:fn, [:i64], [:i64]},
        "memory" => {:memory, %{minimum: 17, shared: false, memory64: false}},
        "string" => {:fn, [], [:i32]},
        "string_first_byte" => {:fn, [:i32, :i32], [:i32]},
        "sum" => {:fn, [:i32, :i32], [:i32]},
        "void" => {:fn, [], []}
      }

      assert expected == Wasmex.Module.exports(module)
    end

    test "lists table data" do
      {:ok, store} = Wasmex.Store.new()

      {:ok, module} =
        Wasmex.Module.compile(store, "(module (table (export \"myTable\") 2 funcref))")

      expected = %{"myTable" => {:table, %{minimum: 2, type: {:reference, "(ref null func)"}}}}
      assert expected == Wasmex.Module.exports(module)
    end

    test "lists function data" do
      {:ok, store} = Wasmex.Store.new()

      {:ok, module} = Wasmex.Module.compile(store, "(module (func (export \"myFunction\")))")

      expected = %{"myFunction" => {:fn, [], []}}
      assert expected == Wasmex.Module.exports(module)
    end

    test "lists memory data" do
      {:ok, store} = Wasmex.Store.new()

      {:ok, module} = Wasmex.Module.compile(store, "(module (memory (export \"myMemory\") 1))")

      expected = %{"myMemory" => {:memory, %{minimum: 1, shared: false, memory64: false}}}
      assert expected == Wasmex.Module.exports(module)
    end

    test "lists no exports for the empty module" do
      {:ok, store} = Wasmex.Store.new()
      {:ok, module} = Wasmex.Module.compile(store, "(module)")
      assert %{} == Wasmex.Module.exports(module)
    end
  end

  describe t(&Module.imports/1) do
    test "lists imports of a module" do
      %{module: module} = TestHelper.wasm_import_module()

      expected = %{
        "env" => %{
          "imported_sum3" => {:fn, [:i32, :i32, :i32], [:i32]},
          "imported_sumf" => {:fn, [:f32, :f32], [:f32]},
          "imported_void" => {:fn, [], []}
        }
      }

      assert expected == Wasmex.Module.imports(module)
    end

    test "lists table data" do
      {:ok, store} = Wasmex.Store.new()

      {:ok, module} =
        Wasmex.Module.compile(
          store,
          "(module (table (import \"env\" \"myTable\") 2 funcref))"
        )

      expected = %{
        "env" => %{"myTable" => {:table, %{minimum: 2, type: {:reference, "(ref null func)"}}}}
      }

      assert expected == Wasmex.Module.imports(module)
    end

    test "lists function data" do
      {:ok, store} = Wasmex.Store.new()

      {:ok, module} =
        Wasmex.Module.compile(store, "(module (func (import \"env\" \"myFunction\")))")

      expected = %{"env" => %{"myFunction" => {:fn, [], []}}}
      assert expected == Wasmex.Module.imports(module)
    end

    test "lists memory data" do
      {:ok, store} = Wasmex.Store.new()

      {:ok, module} =
        Wasmex.Module.compile(store, "(module (memory (import \"env\" \"myMemory\") 1))")

      expected = %{
        "env" => %{"myMemory" => {:memory, %{minimum: 1, shared: false, memory64: false}}}
      }

      assert expected == Wasmex.Module.imports(module)
    end

    test "lists no imports for the empty module" do
      {:ok, store} = Wasmex.Store.new()
      {:ok, module} = Wasmex.Module.compile(store, "(module)")
      assert %{} == Wasmex.Module.imports(module)
    end

    test "groups imports by namespace" do
      wat = """
      (module
        (import "env" "MyMemory" (memory (;0;) 256 256))
        (import "global" "Infinity" (global (;8;) f64))
        (import "global" "NaN" (global (;7;) f64))
        (import "env" "MyTable" (table (;0;) 10 10 funcref))
      )
      """

      {:ok, store} = Wasmex.Store.new()
      {:ok, module} = Wasmex.Module.compile(store, wat)

      expected = %{
        "env" => %{
          "MyMemory" => {:memory, %{maximum: 256, minimum: 256, shared: false, memory64: false}},
          "MyTable" =>
            {:table, %{maximum: 10, minimum: 10, type: {:reference, "(ref null func)"}}}
        },
        "global" => %{
          "Infinity" => {:global, %{mutability: :const, type: :f64}},
          "NaN" => {:global, %{mutability: :const, type: :f64}}
        }
      }

      assert expected == Wasmex.Module.imports(module)
    end
  end
end
