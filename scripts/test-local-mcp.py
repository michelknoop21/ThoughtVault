#!/usr/bin/env python3
"""Exercise the actual macOS HTTP transport with synthetic handlers only."""
import asyncio, importlib.util, json, os, secrets, socket, subprocess, tempfile, urllib.request, urllib.error
from pathlib import Path
root = Path(__file__).resolve().parents[1]
source = (root / 'macos/ViewModels/AIConnectionViewModel.swift').read_text()
server = source[source.index('#if os(macOS)\n@preconcurrency import Network'):]
scope = source[source.index('    static func requiredScope'):source.index('    private func allowed')]
stub = 'import Foundation\nenum AIConnectionError: LocalizedError { case message(String); var errorDescription: String? { if case let .message(s) = self { return s }; return nil } }\n@MainActor final class AIConnectionViewModel {\n' + scope + '}\n'
harness = '''
_ = Task { @MainActor in
    let server = try LocalMCPServer(token: ProcessInfo.processInfo.environment["MCP_TEST_TOKEN"]!, scopes: ["read"], handler: { tool, args in ["synthetic": true, "tool": tool] }, onStatus: { print($0); fflush(stdout) })
    server.start()
    try await Task.sleep(for: .seconds(60))
    server.stop()
}
RunLoop.main.run()
'''
with tempfile.TemporaryDirectory(prefix='thoughtvault-mcp-test-') as folder:
    path = Path(folder)
    (path / 'main.swift').write_text(stub + server + harness)
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'server')], check=True)
    token = secrets.token_hex(32)
    child = subprocess.Popen([str(path / 'server')], env={**os.environ, 'MCP_TEST_TOKEN': token}, stdout=subprocess.PIPE, text=True)
    try:
        ready = child.stdout.readline().strip()
        assert 'actief' in ready, ready
        def call(method, params=None, headers=None):
            body = json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params or {}}).encode()
            req = urllib.request.Request('http://127.0.0.1:11218/mcp', data=body, headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json', **(headers or {})})
            try:
                with urllib.request.urlopen(req, timeout=5) as result: return result.status, json.load(result)
            except urllib.error.HTTPError as error: return error.code, json.load(error)
        assert call('initialize')[1]['result']['serverInfo']['name'] == 'ThoughtVault Mac'
        tools = call('tools/list')[1]['result']['tools']
        assert len(tools) == 7 and all(t['annotations']['readOnlyHint'] for t in tools)
        assert call('tools/call', {'name': 'get_app_state'})[1]['result']['structuredContent']['synthetic']
        assert call('tools/call', {'name': 'start_recording'})[1]['result']['isError']
        assert call('tools/call', {'name': 'unknown'})[1]['result']['isError']
        assert call('initialize', headers={'Authorization': 'Bearer wrong'})[0] == 403
        assert call('initialize', headers={'Origin': 'https://evil.example'})[0] == 403
        assert call('initialize', headers={'Host': 'evil.example'})[0] == 403
        assert call('initialize', headers={'Transfer-Encoding': 'chunked'})[0] == 403
        assert call('initialize', headers={'MCP-Protocol-Version': 'invalid'})[0] == 400
        assert call('initialize')[1]['result']['protocolVersion'] == '2025-06-18'
        request = urllib.request.Request('http://127.0.0.1:11218/mcp', headers={'Authorization': 'Bearer ' + token})
        try: urllib.request.urlopen(request, timeout=5); raise AssertionError('GET accepted')
        except urllib.error.HTTPError as error: assert error.code == 405
        assert call('tools/call', {'name': 'get_app_state', 'arguments': []})[1]['result']['isError']
        with socket.create_connection(('127.0.0.1', 11218), timeout=5) as connection:
            request = f'POST /mcp HTTP/1.1\r\nHost: localhost:11218\r\nAuthorization: Bearer {token}\r\nContent-Length: 0\r\nContent-Length: 1\r\n\r\n'
            connection.sendall(request.encode())
            assert connection.recv(4096).startswith(b'HTTP/1.1 400')
        print('PASS: initialize, 7 read tools, tool execution, denied recording/unknown/token/origin/host/transfer/duplicate headers/invalid arguments')
        if importlib.util.find_spec('mcp'):
            from mcp import ClientSession
            from mcp.client.streamable_http import streamablehttp_client
            async def sdk_check():
                async with streamablehttp_client('http://127.0.0.1:11218/mcp', headers={'Authorization': 'Bearer ' + token}) as (read, write, _):
                    async with ClientSession(read, write) as session:
                        initialized = await session.initialize()
                        assert initialized.protocolVersion == '2025-06-18'
                        assert len((await session.list_tools()).tools) == 7
                        result = await session.call_tool('get_app_state', {})
                        assert not result.isError and result.structuredContent['synthetic']
                        assert (await session.call_tool('start_recording', {})).isError
            asyncio.run(sdk_check())
            print('PASS: installed MCP SDK initialize, list_tools, call_tool and permission denial')
        else:
            print('SKIP: optional MCP SDK not installed; standard-library transport checks passed')
    finally:
        child.terminate(); child.wait(timeout=5)
