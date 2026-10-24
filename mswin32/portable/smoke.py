"""Exercise the copied EXE in an empty directory without provider modules."""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import shutil
import socket
import ssl
import subprocess
import tempfile
import time


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def verify_tcp_client(run):
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        # Ncat client must send and receive bytes over ordinary TCP.
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen()
            listener.settimeout(10)

            def tcp_server():
                with listener.accept()[0] as client:
                    client.settimeout(10)
                    payload = client.recv(4096)
                    check(payload == b'tcp-request\n', 'TCP request corrupted')
                    client.sendall(b'tcp-response\n')

            future = pool.submit(tcp_server)
            proc = run('-w', '5s', '127.0.0.1', listener.getsockname()[1], data=b'tcp-request\n')
            future.result(timeout=12)
            check(proc.stdout == b'tcp-response\n', 'TCP response corrupted')
            return {'tcp_client_roundtrip': 'pass'}


def verify_udp_client(run):
    with socket.socket(type=socket.SOCK_DGRAM) as udp:
        udp.bind(('127.0.0.1', 0))
        udp.settimeout(10)
        proc = run('-u', '--send-only', '127.0.0.1', udp.getsockname()[1], data=b'udp-request')
        check(udp.recvfrom(4096)[0] == b'udp-request', 'UDP request corrupted')
        return {'udp_client': 'pass'}


def create_tls_context(openssl, root):
    # Generate test-only certificate inputs outside the standalone directory.
    cert, key = root / 'cert.pem', root / 'key.pem'
    config = root / 'openssl.cnf'
    config.write_text('[req]\ndistinguished_name = dn\n[dn]\n')
    subprocess.run([openssl, 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                    '-keyout', str(key), '-out', str(cert), '-days', '1',
                    '-config', str(config),
                    '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost'],
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    sni_names = []
    context.set_servername_callback(lambda connection, name, ctx: sni_names.append(name))

    return context, cert, sni_names


def verify_tls_clients(run, context, cert, sni_names):
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        results = {}
        for verify in (False, True):
            with socket.socket() as listener:
                listener.bind(('127.0.0.1', 0))
                listener.listen()
                listener.settimeout(10)

                def tls_server():
                    with listener.accept()[0] as client:
                        client.settimeout(10)
                        with context.wrap_socket(client, server_side=True) as tls:
                            check(tls.recv(4096) == b'tls-request\n', 'TLS request corrupted')
                            tls.sendall(b'tls-response\n')
                            # Send TLS close_notify before closing the TCP socket.
                            # Ncat may close TCP without a reciprocal close_notify.
                            try:
                                tls.unwrap()
                            except (ssl.SSLEOFError, ConnectionResetError):
                                pass

                future = pool.submit(tls_server)
                options = ['-vv', '-w', '5s', '--no-shutdown', '--ssl', '--ssl-servername', 'localhost']
                if verify:
                    options += ['--ssl-verify', '--ssl-trustfile', str(cert)]
                proc = run(*options, '127.0.0.1', listener.getsockname()[1], data=b'tls-request\n')
                future.result(timeout=12)
                check(proc.stdout == b'tls-response\n', 'TLS response corrupted')
                results['tls_verified_client' if verify else 'tls_client'] = 'pass'
        check(sni_names == ['localhost', 'localhost'], 'TLS SNI incorrect')
        results['tls_sni'] = 'pass'
        results['no_external_provider_required'] = 'pass'

        return results


def verify_listeners(exe, isolated, env, root):
    results = {}
    # Ncat listener with Lua execution and Ncat TLS listener with auto certificate.
    for use_tls in (False, True):
        with socket.socket() as reserve:
            reserve.bind(('127.0.0.1', 0))
            port = reserve.getsockname()[1]
        script = root / 'test.lua'
        script.write_text('io.write("lua-response\\n"); io.flush()\n')
        options = ['-l', '127.0.0.1', str(port)]
        if use_tls:
            options += ['--ssl', '--send-only']
        else:
            options += ['--lua-exec', str(script)]
        proc = subprocess.Popen([str(exe), *options], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                cwd=isolated, env=env)
        try:
            client = None
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                try:
                    client = socket.create_connection(('127.0.0.1', port), timeout=1)
                    break
                except (ConnectionRefusedError, TimeoutError):
                    if proc.poll() is not None:
                        raise AssertionError(proc.stderr.read().decode(errors='replace'))
                    time.sleep(0.1)
            check(client is not None, 'Ncat listener did not start')
            with client:
                client.settimeout(10)
                if use_tls:
                    client_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
                    client_context.check_hostname = False
                    client_context.verify_mode = ssl.CERT_NONE
                    with client_context.wrap_socket(client, server_hostname='localhost') as tls:
                        proc.stdin.write(b'tls-listener\n')
                        proc.stdin.flush()
                        check(tls.recv(4096) == b'tls-listener\n', 'TLS listener response corrupted')
                else:
                    check(client.recv(4096) == b'lua-response\n', 'Lua response corrupted')
            stdout, stderr = proc.communicate(timeout=10)
            check(proc.returncode == 0, stderr.decode(errors='replace'))
            check(b'provider failed to load' not in stderr, stderr.decode(errors='replace'))
            results['tls_listener_auto_certificate' if use_tls else 'tcp_listener_lua'] = 'pass'
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate()

    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--exe', required=True)
    parser.add_argument('--openssl', required=True)
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    report = Path(args.report).resolve()
    openssl = str(Path(args.openssl).resolve())
    results = {}
    with tempfile.TemporaryDirectory(prefix='ncat-portable-') as scratch:
        root = Path(scratch)
        isolated = root / 'standalone'
        isolated.mkdir()
        exe = isolated / 'ncat.exe'
        shutil.copy2(args.exe, exe)
        env = os.environ.copy()
        env['PATH'] = str(Path(env['SYSTEMROOT']) / 'System32')
        env['OPENSSL_MODULES'] = str(root / 'missing-modules')
        env['OPENSSL_CONF'] = str(root / 'missing-openssl.cnf')

        def run(*options, data=b''):
            proc = subprocess.run([str(exe), *map(str, options)], input=data,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  cwd=isolated, env=env, timeout=15)
            check(proc.returncode == 0, proc.stderr.decode(errors='replace'))
            check(b'provider failed to load' not in proc.stderr,
                  proc.stderr.decode(errors='replace'))
            return proc

        version = run('--version')
        results['version'] = (version.stdout + version.stderr).decode().strip()
        check('Ncat: Version ' in results['version'], 'Missing Ncat version output')
        help_text = run('--help').stdout
        check(b'--ssl' in help_text and b'--lua-exec' in help_text, 'Missing TLS or Lua')

        results.update(verify_tcp_client(run))
        results.update(verify_udp_client(run))
        context, cert, sni_names = create_tls_context(openssl, root)
        results.update(verify_tls_clients(run, context, cert, sni_names))
        results.update(verify_listeners(exe, isolated, env, root))

        check([p.name for p in isolated.iterdir()] == ['ncat.exe'], 'Unexpected companion files')
        results['only_exe_in_runtime_directory'] = 'pass'
    report.write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
