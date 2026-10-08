"""Run standalone qiqi Lua tests in both supported language engines."""
import argparse
import importlib
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1] / 'qiqiappstore.koplugin'
fallback = ROOT.parent / '.testdeps312'
if fallback.exists():
    sys.path.insert(0, str(fallback))

def runtime(engine):
    lua = importlib.import_module('lupa.' + engine).LuaRuntime(unpack_returned_tuples=True)
    lua.execute('package.path = ' + repr(str(ROOT).replace('\\', '/') + '/?.lua;') + ' .. package.path')
    lua.execute('os.exit = function(code) assert(code == nil or code == 0, "Lua test requested failure exit") end')
    return lua

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('files', nargs='*')
    args = parser.parse_args()
    os.chdir(ROOT)
    files = [Path(p) for p in args.files] or sorted((ROOT.parent / 'tests').glob('qiqi_*_test.lua')) + [ROOT.parent / 'tests/qiqiappstore_dir_collision_test.lua']
    count = 0
    for engine in ('lua51', 'luajit21'):
        for path in files:
            lua = runtime(engine)
            lua.execute(path.read_text(encoding='utf-8'))
            print(f'PASS {engine} {path.name}')
            count += 1
        lua = runtime(engine)
        compiler = lua.eval('function(s,n) local f,e=loadstring(s,n); assert(f,e); return true end')
        for path in sorted(ROOT.rglob('*.lua')):
            if '.git' not in path.parts:
                compiler(path.read_text(encoding='utf-8'), str(path))
        print(f'PASS {engine} all Lua syntax')
    print(f'{count} test suites passed across both engines')

if __name__ == '__main__':
    main()
