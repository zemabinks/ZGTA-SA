#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual bounded Foundation HTTP + installed resolver; authored bytes only."""
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import argparse,gzip,hashlib,json,os,signal,subprocess,threading,time

ROOT=Path(__file__).resolve().parent
SOURCES=['ServerAddress.swift','NativeStockAssetAccess.swift','NativeResourceManifest.swift','NativeResourceStore.swift','NativeResourceSession.swift']
def sha(value):return hashlib.sha256(value).hexdigest()
def run(command,log,budget):
    process=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,start_new_session=True,text=True)
    timed_out=False
    try:text,_=process.communicate(timeout=budget)
    except subprocess.TimeoutExpired:
        timed_out=True;os.killpg(process.pid,signal.SIGTERM)
        try:text,_=process.communicate(timeout=5)
        except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);text,_=process.communicate()
    log.write_text(text)
    return {'exitCode':process.returncode,'timedOut':timed_out,'command':command}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--reuse-run',type=Path);args=parser.parse_args()
    out=ROOT/'local-only/research/bounded-resources-119'/('run-'+str(time.time_ns()));snapshot=out/'source';snapshot.mkdir(parents=True)
    paths=[ROOT/'ios/App'/name for name in SOURCES]+[ROOT/'test_native_bounded_resources.swift',ROOT/'test_native_bounded_resources.py']
    before={str(p.relative_to(ROOT)):p.read_bytes() for p in paths}
    for name,body in before.items():
        target=snapshot/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(body)
    report={'status':'NOT_RUN','sourceSHA256':{n:sha(v) for n,v in before.items()},'output':str(out),'actualNice':os.getpriority(os.PRIO_PROCESS,0),'limits':['Synthetic resource bodies and explicitly synthetic Store runtime validator, not engine/GPU/retail acceptance.','Retained payload Data.count is bounded; Foundation delegate chunks, HTTP parser, allocator capacity and kernel buffers are outside this application-owned bound.','No game assets, App container, browser/device/window or persistent service touched.']}
    save=lambda:(out/'acceptance.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    if report['actualNice']!=15:raise RuntimeError('Run this bounded gate at actual nice15; no priority fallback')
    if args.reuse_run:
        prior=args.reuse_run.resolve();receipt=json.loads((prior/'acceptance.json').read_text());executable=prior/'bounded-tests'
        swift_names=[n for n in before if n.endswith('.swift')]
        valid=all(receipt['sourceSHA256'].get(n)==sha(before[n])==sha((prior/'source'/n).read_bytes()) for n in swift_names)
        valid=valid and receipt['compile']['exitCode']==0 and not receipt['compile']['timedOut'] and receipt['executableSHA256']==sha(executable.read_bytes())
        if not valid:raise RuntimeError('Executable reuse requires exact retained/current Swift source, harness and binary proof')
        report['reusedExecutable']={'receipt':str(prior/'acceptance.json'),'receiptSHA256':sha((prior/'acceptance.json').read_bytes()),'swiftSourceIdentical':True}
    else:
        standalone=['xcrun','swiftc','-swift-version','5','-typecheck','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',str(snapshot/'ios/App/ServerAddress.swift')]
        report['standaloneFoundation']=run(standalone,out/'standalone.log',900);save()
        if report['standaloneFoundation']['exitCode'] or report['standaloneFoundation']['timedOut']:
            report['status']='STANDALONE_FAILED';save();print((out/'standalone.log').read_text()[-5000:]);raise SystemExit(1)
        executable=out/'bounded-tests'
        command=['xcrun','swiftc','-swift-version','5','-parse-as-library','-whole-module-optimization','-Onone','-num-threads','1','-module-cache-path','/private/tmp/zgtasa-core-swift-modules']+[str(snapshot/'ios/App'/n) for n in SOURCES]+[str(snapshot/'test_native_bounded_resources.swift'),'-o',str(executable)]
        report['compile']=run(command,out/'compile.log',900);save()
        if report['compile']['exitCode'] or report['compile']['timedOut']:
            report['status']='COMPILE_FAILED';save();print((out/'compile.log').read_text()[-5000:]);raise SystemExit(1)
    report['executableSHA256']=sha(executable.read_bytes())
    counts={};lock=threading.Lock()
    class Handler(BaseHTTPRequestHandler):
        protocol_version='HTTP/1.1'
        def log_message(self,*args):pass
        def do_HEAD(self):self.do_GET()
        def do_GET(self):
            with lock:counts[self.path]=counts.get(self.path,0)+1
            path=self.path;body=b'';headers={};status=200
            if path.startswith('/bytes/'):
                n=int(path.rsplit('/',1)[1]);body=bytes(i%251 for i in range(n))
            elif path=='/unknown-length':body=bytes(i%251 for i in range(4096))
            elif path.startswith('/chunked/'):
                n=int(path.rsplit('/',1)[1]);self.send_response(200);self.send_header('Transfer-Encoding','chunked');self.end_headers()
                try:
                    for offset in range(0,n,127):
                        part=bytes(i%251 for i in range(offset,min(n,offset+127)))
                        self.wfile.write(('%x\r\n'%len(part)).encode()+part+b'\r\n');self.wfile.flush()
                    self.wfile.write(b'0\r\n\r\n');self.wfile.flush()
                except (BrokenPipeError,ConnectionResetError):pass
                return
            elif path=='/declared':headers['Content-Length']='2147483647';body=b'x'*16384
            elif path=='/gzip':body=gzip.compress(b'authored'*1000);headers['Content-Encoding']='gzip'
            elif path=='/redirect':status=302;headers['Location']=sink_origin+'/must-not-leak'
            elif path=='/short':body=b'short';headers['Content-Length']='10'
            elif path=='/bad-length':body=b'x';headers['Content-Length']='invalid'
            elif path=='/conflicting-length':body=b'1234';headers['Content-Length']='4, 5'
            elif path=='/status':status=503;body=b'authored denial'
            elif path=='/slow':body=b'x'*4096
            elif path in ['/api/echo','/api/echo-disabled']:body=json.dumps({'cookie':'authored-bounded=synthetic-only' in self.headers.get('Cookie',''),'identity':self.headers.get('Accept-Encoding')=='identity'}).encode()
            elif path=='/game/native/bounded.bin':body=b'development-network-body'
            else:body=b'UNEXPECTED NETWORK';status=404
            self.send_response(status)
            for name,value in headers.items():self.send_header(name,value)
            if 'Content-Length' not in headers and path!='/unknown-length':self.send_header('Content-Length',str(len(body)))
            self.send_header('Connection','close');self.end_headers()
            try:
                if self.command!='HEAD':
                    if path=='/slow':
                        for offset in range(0,len(body),64):self.wfile.write(body[offset:offset+64]);self.wfile.flush();time.sleep(.02)
                    else:
                        self.wfile.write(body);self.wfile.flush()
                        if path=='/declared':time.sleep(.3)
            except (BrokenPipeError,ConnectionResetError):pass
            self.close_connection=True
    servers=[]
    try:
        sink=ThreadingHTTPServer(('127.0.0.1',0),Handler);servers.append(sink)
        sink_origin='http://127.0.0.1:'+str(sink.server_port)
        host=ThreadingHTTPServer(('127.0.0.1',0),Handler);servers.append(host)
        for server in servers:threading.Thread(target=server.serve_forever,daemon=True).start()
        config=out/'config.json';config.write_text(json.dumps({'origin':'http://127.0.0.1:'+str(host.server_port),'work':str(out/'fixture')}))
        report['runtime']=run([str(executable),str(config)],out/'run.log',120)
    finally:
        for server in servers:server.shutdown();server.server_close()
    report['requests']=dict(counts)
    report['sourceUnchanged']=all((ROOT/name).read_bytes()==body for name,body in before.items())
    suite=out/'fixture/report.json'
    if suite.is_file():report['suite']=json.loads(suite.read_text())
    report['httpChecks']={
        'invalidAndPrecancelMadeNoRequest':counts.get('/must-not-request',0)==0,
        'redirectNeverReachedSecondOrigin':counts.get('/must-not-leak',0)==0,
        'installedKnownOnlyDevelopmentReadReachedNetwork':counts.get('/game/native/bounded.bin',0)==1,
        'installedUnknownNeverReachedNetwork':counts.get('/game/native/absent.bin',0)==0,
        'invalidQueryNeverReachedNetwork':not any('invalid=1' in p for p in counts),
        'ordinaryAPIStayedNetwork':counts.get('/api/echo',0)==1,
    }
    ok=report['runtime']['exitCode']==0 and not report['runtime']['timedOut'] and report.get('suite',{}).get('status')=='PASS' and report['sourceUnchanged'] and all(report['httpChecks'].values())
    report['status']='PASS' if ok else 'FAILED';save();print(json.dumps(report,indent=2))
    if not ok:print((out/'run.log').read_text()[-5000:]);raise SystemExit(1)
if __name__=='__main__':main()
