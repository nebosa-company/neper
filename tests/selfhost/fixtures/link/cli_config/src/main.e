// `e.cli.config` against scripts/config_vectors.py (collections.ChainMap for precedence,
// configparser and json for the file layer): 40 scenarios of defaults, an INI or JSON file, an
// environment and flags, 403 reads each checked for value, winning layer and typed answers; then
// reload and change counting on a real file, a real `e.cli` parse into the flag layer, and the
// watcher coalescing three writes of a file into one reload.
use e.cli
use e.cli.config as config
use e.fs
use e.fs.watch as watch
use e.io
use e.mem
use e.os
use e.thread
use e.str

fn vectors() -> str {
    ret "S~json~7b226462223a207b22706f6f6c223a207b2273697a65223a20383038307d7d2c2022736572766572223a207b22706f7274223a202246414c5345227d2c202266656174757265223a207b2262657461223a20224f6666227d2c2022657874726173223a205b2261222c20312c20747275652c206e756c6c2c207b226b223a202276227d5d7d~db.pool.size=0~APP_EXTRAS_1=true~log.json=8080;log.level=FALSE\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~-~-~-~-~-\nQ~db.pool.size~8080~f~ok:8080~ok:8080.000000~bad\nQ~extras.0~a~f~bad~bad~bad\nQ~extras.1~true~e~bad~bad~ok:true\nQ~extras.2~true~f~bad~bad~ok:true\nQ~extras.4.k~v~f~bad~bad~bad\nQ~feature.beta~Off~f~bad~bad~ok:false\nQ~log.json~8080~l~ok:8080~ok:8080.000000~bad\nQ~log.level~FALSE~l~bad~bad~ok:false\nQ~name~-~-~-~-~-\nQ~server.nope~-~-~-~-~-\nQ~server.port~FALSE~f~bad~bad~ok:false\nS~ini~5b6c6f675d0a6a736f6e3d78310a6c6576656c203d20302e3132350a0a5b666561747572655d0a626574613d747275650a0a5b7365727665725d0a686f73743d4f66660a0a~log.level=FALSE~APP_FEATURE_BETA=x1;APP_SERVER_HOST=hello~name=true;ratio=Off;feature.beta=8080\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~-~-~-~-~-\nQ~feature.beta~8080~l~ok:8080~ok:8080.000000~bad\nQ~log.json~x1~f~bad~bad~bad\nQ~log.level~0.125~f~bad~ok:0.125000~bad\nQ~name~true~l~bad~bad~ok:true\nQ~ratio~Off~l~bad~bad~ok:false\nQ~server.host~hello~e~bad~bad~bad\nQ~server.nope~-~-~-~-~-\nS~json~7b2266656174757265223a207b2262657461223a20224f6666227d7d~ratio=1;feature.beta=0;db.pool.size=hello;log.level=true;server.host=8080;server.port=true~APP_RATIO=debug;APP_SERVER_PORT=2.5~log.level=FALSE;extra.flag=x1;ratio=yes\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~-~-~-~-~-\nQ~db.pool.size~hello~d~bad~bad~bad\nQ~extra.flag~x1~l~bad~bad~bad\nQ~feature.beta~Off~f~bad~bad~ok:false\nQ~log.json~-~-~-~-~-\nQ~log.level~FALSE~l~bad~bad~ok:false\nQ~name~-~-~-~-~-\nQ~ratio~yes~l~bad~bad~ok:true\nQ~server.host~8080~d~ok:8080~ok:8080.000000~bad\nQ~server.nope~-~-~-~-~-\nQ~server.port~2.5~e~bad~ok:2.500000~bad\nS~ini~5b7365727665725d0a686f7374203d2046414c53450a0a5b666561747572655d0a626574613d300a0a5b6c6f675d0a6a736f6e203d204f66660a6c6576656c203d2068656c6c6f0a0a5b64625d0a706f6f6c2e6d61783d64656275670a~db.pool.size=true~APP_DB_POOL_MAX=hello;APP_SERVER_HOST=-3~server.port=hello;log.level=2.5;db.pool.max=debug\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~debug~l~bad~bad~bad\nQ~db.pool.size~true~d~bad~bad~ok:true\nQ~feature.beta~0~f~ok:0~ok:0.000000~ok:false\nQ~log.json~Off~f~bad~bad~ok:false\nQ~log.level~2.5~l~bad~ok:2.500000~bad\nQ~server.host~-3~e~ok:-3~ok:-3.000000~bad\nQ~server.nope~-~-~-~-~-\nQ~server.port~hello~l~bad~bad~bad\nS~json~7b0a20202266656174757265223a207b0a202020202262657461223a202d330a20207d2c0a2020226e616d65223a2022796573222c0a202022736572766572223a207b0a2020202022686f7374223a202268656c6c6f220a20207d2c0a2020226462223a207b0a2020202022706f6f6c223a207b0a202020202020226d6178223a202238303830220a202020207d0a20207d0a7d~db.pool.max=Off;log.level=0;db.pool.size=hello;ratio=-3~APP_SERVER_HOST=x1;APP_UNKNOWN_KEY=8080~name=true\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~8080~f~ok:8080~ok:8080.000000~bad\nQ~db.pool.size~hello~d~bad~bad~bad\nQ~feature.beta~-3~f~ok:-3~ok:-3.000000~bad\nQ~log.level~0~d~ok:0~ok:0.000000~ok:false\nQ~name~true~l~bad~bad~ok:true\nQ~ratio~-3~d~ok:-3~ok:-3.000000~bad\nQ~server.host~x1~e~bad~bad~bad\nQ~server.nope~-~-~-~-~-\nS~ini~5b666561747572655d0a62657461203d20383038300a0a~server.port=8080;feature.beta=Off;log.level=0;db.pool.size=2.5;db.pool.max=Off~~server.port=Off;db.pool.max=Off\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~Off~l~bad~bad~ok:false\nQ~db.pool.size~2.5~d~bad~ok:2.500000~bad\nQ~feature.beta~8080~f~ok:8080~ok:8080.000000~bad\nQ~log.json~-~-~-~-~-\nQ~log.level~0~d~ok:0~ok:0.000000~ok:false\nQ~ratio~-~-~-~-~-\nQ~server.host~-~-~-~-~-\nQ~server.nope~-~-~-~-~-\nQ~server.port~Off~l~bad~bad~ok:false\nS~json~7b0a202022726174696f223a202230222c0a2020226462223a207b0a2020202022706f6f6c223a207b0a202020202020226d6178223a20226465627567222c0a2020202020202273697a65223a20747275650a202020207d0a20207d2c0a2020226e616d65223a20383038302c0a202022657874726173223a205b0a202020202261222c0a20202020312c0a20202020747275652c0a202020206e756c6c2c0a202020207b0a202020202020226b223a202276220a202020207d0a20205d0a7d~ratio=-3;db.pool.max=1;log.json=hello;server.port=8080;db.pool.size=x1~APP_NAME=true~log.level=FALSE\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~debug~f~bad~bad~bad\nQ~db.pool.size~true~f~bad~bad~ok:true\nQ~extras.0~a~f~bad~bad~bad\nQ~extras.1~1~f~ok:1~ok:1.000000~ok:true\nQ~extras.2~true~f~bad~bad~ok:true\nQ~extras.4.k~v~f~bad~bad~bad\nQ~log.json~hello~d~bad~bad~bad\nQ~log.level~FALSE~l~bad~bad~ok:false\nQ~name~true~e~bad~bad~ok:true\nQ~ratio~0~f~ok:0~ok:0.000000~ok:false\nQ~server.nope~-~-~-~-~-\nQ~server.port~8080~d~ok:8080~ok:8080.000000~bad\nS~ini~5b6c6f675d0a6c6576656c203d20310a6a736f6e3d302e3132350a0a5b7365727665725d0a686f73743d46414c53450a0a5b64625d0a706f6f6c2e6d6178203d20300a~log.level=Off~APP_UNKNOWN_KEY=debug;APP_LOG_LEVEL=yes;APP_DB_POOL_MAX=Off~db.pool.max=-3;server.host=0\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~-3~l~ok:-3~ok:-3.000000~bad\nQ~db.pool.size~-~-~-~-~-\nQ~feature.beta~-~-~-~-~-\nQ~log.json~0.125~f~bad~ok:0.125000~bad\nQ~log.level~yes~e~bad~bad~ok:true\nQ~server.host~0~l~ok:0~ok:0.000000~ok:false\nQ~server.nope~-~-~-~-~-\nS~json~7b22736572766572223a207b22686f7374223a20226465627567227d2c20226462223a207b22706f6f6c223a207b226d6178223a202246414c5345227d7d2c2022657874726173223a205b2261222c20312c20747275652c206e756c6c2c207b226b223a202276227d5d7d~server.host=Off;ratio=1~APP_EXTRAS_4_K=FALSE;APP_EXTRAS_0=true~server.host=hello;extra.flag=-3;ratio=2.5\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~FALSE~f~bad~bad~ok:false\nQ~extra.flag~-3~l~ok:-3~ok:-3.000000~bad\nQ~extras.0~true~e~bad~bad~ok:true\nQ~extras.1~1~f~ok:1~ok:1.000000~ok:true\nQ~extras.2~true~f~bad~bad~ok:true\nQ~extras.4.k~FALSE~e~bad~bad~ok:false\nQ~name~-~-~-~-~-\nQ~ratio~2.5~l~bad~ok:2.500000~bad\nQ~server.host~hello~l~bad~bad~bad\nQ~server.nope~-~-~-~-~-\nS~ini~5b64625d0a706f6f6c2e73697a65203d204f66660a0a5b666561747572655d0a626574613d300a0a5b6c6f675d0a6c6576656c203d2068656c6c6f0a0a5b7365727665725d0a706f72743d46414c53450a0a~server.host=yes~APP_SERVER_PORT=yes;APP_LOG_LEVEL=-3;APP_FEATURE_BETA=2.5~log.json=8080\nQ~absent.one~-~-~-~-~-\nQ~db.pool.size~Off~f~bad~bad~ok:false\nQ~feature.beta~2.5~e~bad~ok:2.500000~bad\nQ~log.json~8080~l~ok:8080~ok:8080.000000~bad\nQ~log.level~-3~e~ok:-3~ok:-3.000000~bad\nQ~name~-~-~-~-~-\nQ~server.host~yes~d~bad~bad~ok:true\nQ~server.nope~-~-~-~-~-\nQ~server.port~yes~e~bad~bad~ok:true\nS~json~7b0a2020226e616d65223a202238303830220a7d~db.pool.size=0.125;log.level=hello;ratio=hello;server.host=true~APP_RATIO=2.5~feature.beta=FALSE;name=0;log.json=yes\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~-~-~-~-~-\nQ~db.pool.size~0.125~d~bad~ok:0.125000~bad\nQ~feature.beta~FALSE~l~bad~bad~ok:false\nQ~log.json~yes~l~bad~bad~ok:true\nQ~log.level~hello~d~bad~bad~bad\nQ~name~0~l~ok:0~ok:0.000000~ok:false\nQ~ratio~2.5~e~bad~ok:2.500000~bad\nQ~server.host~true~d~bad~bad~ok:true\nQ~server.nope~-~-~-~-~-\nQ~server.port~-~-~-~-~-\nS~ini~5b666561747572655d0a62657461203d2064656275670a0a5b7365727665725d0a686f7374203d20300a0a5b64625d0a706f6f6c2e73697a65203d2078310a0a5b6c6f675d0a6c6576656c3d68656c6c6f0a~db.pool.size=2.5;log.level=FALSE;db.pool.max=8080;feature.beta=0~~server.port=true\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~8080~d~ok:8080~ok:8080.000000~bad\nQ~db.pool.size~x1~f~bad~bad~bad\nQ~feature.beta~debug~f~bad~bad~bad\nQ~log.level~hello~f~bad~bad~bad\nQ~name~-~-~-~-~-\nQ~server.host~0~f~ok:0~ok:0.000000~ok:false\nQ~server.nope~-~-~-~-~-\nQ~server.port~true~l~bad~bad~ok:true\nS~json~7b22736572766572223a207b22686f7374223a20747275657d2c20226462223a207b22706f6f6c223a207b2273697a65223a20227831222c20226d6178223a20383038307d7d2c20226c6f67223a207b226c6576656c223a20322e352c20226a736f6e223a20383038307d7d~server.host=x1;db.pool.max=FALSE;log.json=true;server.port=hello;ratio=-3;db.pool.size=0~APP_RATIO=true;APP_LOG_LEVEL=hello;APP_UNKNOWN_KEY=-3;APP_LOG_JSON=FALSE~\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~8080~f~ok:8080~ok:8080.000000~bad\nQ~db.pool.size~x1~f~bad~bad~bad\nQ~log.json~FALSE~e~bad~bad~ok:false\nQ~log.level~hello~e~bad~bad~bad\nQ~ratio~true~e~bad~bad~ok:true\nQ~server.host~true~f~bad~bad~ok:true\nQ~server.nope~-~-~-~-~-\nQ~server.port~hello~d~bad~bad~bad\nS~ini~5b6c6f675d0a6c6576656c203d204f66660a6a736f6e203d204f66660a0a5b64625d0a706f6f6c2e6d61783d2d330a706f6f6c2e73697a653d383038300a0a5b666561747572655d0a62657461203d2046414c53450a~log.level=hello;log.json=hello;server.host=0;server.port=2.5;db.pool.max=2.5~APP_DB_POOL_SIZE=-3~\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~-3~f~ok:-3~ok:-3.000000~bad\nQ~db.pool.size~-3~e~ok:-3~ok:-3.000000~bad\nQ~feature.beta~FALSE~f~bad~bad~ok:false\nQ~log.json~Off~f~bad~bad~ok:false\nQ~log.level~Off~f~bad~bad~ok:false\nQ~server.host~0~d~ok:0~ok:0.000000~ok:false\nQ~server.nope~-~-~-~-~-\nQ~server.port~2.5~d~bad~ok:2.500000~bad\nS~json~7b0a202022736572766572223a207b0a2020202022706f7274223a20747275650a20207d2c0a202022726174696f223a202268656c6c6f222c0a20202266656174757265223a207b0a202020202262657461223a202d330a20207d2c0a2020226c6f67223a207b0a20202020226a736f6e223a202d330a20207d2c0a202022657874726173223a205b0a202020202261222c0a20202020312c0a20202020747275652c0a202020206e756c6c2c0a202020207b0a202020202020226b223a202276220a202020207d0a20205d0a7d~server.port=yes;name=2.5;log.level=8080;feature.beta=0;db.pool.max=0~APP_EXTRAS_0=-3~feature.beta=x1;log.level=FALSE\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~0~d~ok:0~ok:0.000000~ok:false\nQ~extras.0~-3~e~ok:-3~ok:-3.000000~bad\nQ~extras.1~1~f~ok:1~ok:1.000000~ok:true\nQ~extras.2~true~f~bad~bad~ok:true\nQ~extras.4.k~v~f~bad~bad~bad\nQ~feature.beta~x1~l~bad~bad~bad\nQ~log.json~-3~f~ok:-3~ok:-3.000000~bad\nQ~log.level~FALSE~l~bad~bad~ok:false\nQ~name~2.5~d~bad~ok:2.500000~bad\nQ~ratio~hello~f~bad~bad~bad\nQ~server.nope~-~-~-~-~-\nQ~server.port~true~f~bad~bad~ok:true\nS~ini~0a~log.level=x1;db.pool.size=hello;db.pool.max=true~APP_LOG_LEVEL=FALSE;APP_DB_POOL_MAX=2.5~server.host=x1;feature.beta=x1;server.port=-3\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~2.5~e~bad~ok:2.500000~bad\nQ~db.pool.size~hello~d~bad~bad~bad\nQ~feature.beta~x1~l~bad~bad~bad\nQ~log.level~FALSE~e~bad~bad~ok:false\nQ~server.host~x1~l~bad~bad~bad\nQ~server.nope~-~-~-~-~-\nQ~server.port~-3~l~ok:-3~ok:-3.000000~bad\nS~json~7b22736572766572223a207b22686f7374223a202230227d2c20226c6f67223a207b226c6576656c223a20226465627567227d2c202266656174757265223a207b2262657461223a20383038307d2c20226462223a207b22706f6f6c223a207b226d6178223a202246414c5345222c202273697a65223a20227831227d7d2c2022657874726173223a205b2261222c20312c20747275652c206e756c6c2c207b226b223a202276227d5d7d~name=8080;db.pool.max=Off;server.host=0.125;server.port=debug;feature.beta=8080;log.json=2.5~APP_FEATURE_BETA=0;APP_SERVER_HOST=0;APP_SERVER_PORT=8080~log.level=hello\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~FALSE~f~bad~bad~ok:false\nQ~db.pool.size~x1~f~bad~bad~bad\nQ~extras.0~a~f~bad~bad~bad\nQ~extras.1~1~f~ok:1~ok:1.000000~ok:true\nQ~extras.2~true~f~bad~bad~ok:true\nQ~extras.4.k~v~f~bad~bad~bad\nQ~feature.beta~0~e~ok:0~ok:0.000000~ok:false\nQ~log.json~2.5~d~bad~ok:2.500000~bad\nQ~log.level~hello~l~bad~bad~bad\nQ~name~8080~d~ok:8080~ok:8080.000000~bad\nQ~server.host~0~e~ok:0~ok:0.000000~ok:false\nQ~server.nope~-~-~-~-~-\nQ~server.port~8080~e~ok:8080~ok:8080.000000~bad\nS~ini~5b64625d0a706f6f6c2e6d61783d68656c6c6f0a706f6f6c2e73697a65203d20322e350a0a5b7365727665725d0a686f7374203d2068656c6c6f0a0a5b6c6f675d0a6a736f6e3d78310a~feature.beta=1;db.pool.max=1;db.pool.size=debug;server.host=-3;log.json=Off~APP_SERVER_HOST=1;APP_UNKNOWN_KEY=hello~log.json=8080;log.level=true\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~hello~f~bad~bad~bad\nQ~db.pool.size~2.5~f~bad~ok:2.500000~bad\nQ~feature.beta~1~d~ok:1~ok:1.000000~ok:true\nQ~log.json~8080~l~ok:8080~ok:8080.000000~bad\nQ~log.level~true~l~bad~bad~ok:true\nQ~name~-~-~-~-~-\nQ~server.host~1~e~ok:1~ok:1.000000~ok:true\nQ~server.nope~-~-~-~-~-\nQ~server.port~-~-~-~-~-\nS~json~7b0a202022726174696f223a202268656c6c6f222c0a2020226462223a207b0a2020202022706f6f6c223a207b0a202020202020226d6178223a202246414c5345222c0a2020202020202273697a65223a20227831220a202020207d0a20207d2c0a2020226c6f67223a207b0a20202020226c6576656c223a20227831220a20207d0a7d~log.level=Off;server.port=x1;feature.beta=2.5;log.json=hello~APP_UNKNOWN_KEY=2.5;APP_DB_POOL_SIZE=0~\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~FALSE~f~bad~bad~ok:false\nQ~db.pool.size~0~e~ok:0~ok:0.000000~ok:false\nQ~feature.beta~2.5~d~bad~ok:2.500000~bad\nQ~log.json~hello~d~bad~bad~bad\nQ~log.level~x1~f~bad~bad~bad\nQ~ratio~hello~f~bad~bad~bad\nQ~server.nope~-~-~-~-~-\nQ~server.port~x1~d~bad~bad~bad\nS~ini~5b7365727665725d0a706f72743d2d330a686f7374203d2068656c6c6f0a0a5b6c6f675d0a6a736f6e203d20302e3132350a0a5b64625d0a706f6f6c2e73697a653d747275650a0a5b666561747572655d0a62657461203d204f66660a~feature.beta=2.5;db.pool.size=Off~APP_SERVER_HOST=yes;APP_DB_POOL_SIZE=yes;APP_LOG_JSON=8080~\nQ~absent.one~-~-~-~-~-\nQ~db.pool.size~yes~e~bad~bad~ok:true\nQ~feature.beta~Off~f~bad~bad~ok:false\nQ~log.json~8080~e~ok:8080~ok:8080.000000~bad\nQ~server.host~yes~e~bad~bad~ok:true\nQ~server.nope~-~-~-~-~-\nQ~server.port~-3~f~ok:-3~ok:-3.000000~bad\nS~json~7b22736572766572223a207b22686f7374223a202d337d2c20226462223a207b22706f6f6c223a207b226d6178223a20302e3132357d7d2c2022726174696f223a20747275657d~db.pool.max=hello;log.json=yes;server.host=2.5;server.port=hello;name=yes~APP_LOG_JSON=Off;APP_SERVER_HOST=FALSE;APP_DB_POOL_MAX=FALSE;APP_RATIO=debug~server.port=true;log.json=2.5;log.level=true\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~FALSE~e~bad~bad~ok:false\nQ~feature.beta~-~-~-~-~-\nQ~log.json~2.5~l~bad~ok:2.500000~bad\nQ~log.level~true~l~bad~bad~ok:true\nQ~name~yes~d~bad~bad~ok:true\nQ~ratio~debug~e~bad~bad~bad\nQ~server.host~FALSE~e~bad~bad~ok:false\nQ~server.nope~-~-~-~-~-\nQ~server.port~true~l~bad~bad~ok:true\nS~ini~5b64625d0a706f6f6c2e6d61783d383038300a706f6f6c2e73697a65203d20300a0a5b6c6f675d0a6a736f6e3d46414c53450a6c6576656c3d302e3132350a0a5b666561747572655d0a62657461203d20383038300a~server.port=0;server.host=FALSE~APP_FEATURE_BETA=FALSE;APP_DB_POOL_MAX=Off;APP_SERVER_PORT=true;APP_LOG_JSON=8080~db.pool.size=true\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~Off~e~bad~bad~ok:false\nQ~db.pool.size~true~l~bad~bad~ok:true\nQ~feature.beta~FALSE~e~bad~bad~ok:false\nQ~log.json~8080~e~ok:8080~ok:8080.000000~bad\nQ~log.level~0.125~f~bad~ok:0.125000~bad\nQ~name~-~-~-~-~-\nQ~server.host~FALSE~d~bad~bad~ok:false\nQ~server.nope~-~-~-~-~-\nQ~server.port~true~e~bad~bad~ok:true\nS~json~7b0a2020226c6f67223a207b0a20202020226a736f6e223a2022796573220a20207d2c0a202022657874726173223a205b0a202020202261222c0a20202020312c0a20202020747275652c0a202020206e756c6c2c0a202020207b0a202020202020226b223a202276220a202020207d0a20205d0a7d~ratio=0.125;log.json=x1~APP_RATIO=x1;APP_EXTRAS_4_K=0.125;APP_UNKNOWN_KEY=FALSE~server.port=yes;feature.beta=0\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~-~-~-~-~-\nQ~extras.0~a~f~bad~bad~bad\nQ~extras.1~1~f~ok:1~ok:1.000000~ok:true\nQ~extras.2~true~f~bad~bad~ok:true\nQ~extras.4.k~0.125~e~bad~ok:0.125000~bad\nQ~feature.beta~0~l~ok:0~ok:0.000000~ok:false\nQ~log.json~yes~f~bad~bad~ok:true\nQ~ratio~x1~e~bad~bad~bad\nQ~server.nope~-~-~-~-~-\nQ~server.port~yes~l~bad~bad~ok:true\nS~ini~5b64625d0a706f6f6c2e6d61783d46414c53450a0a~log.json=2.5;db.pool.max=x1;db.pool.size=0.125;log.level=-3;feature.beta=Off~APP_LOG_JSON=yes;APP_LOG_LEVEL=debug;APP_DB_POOL_MAX=hello;APP_DB_POOL_SIZE=-3~db.pool.max=debug\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~debug~l~bad~bad~bad\nQ~db.pool.size~-3~e~ok:-3~ok:-3.000000~bad\nQ~feature.beta~Off~d~bad~bad~ok:false\nQ~log.json~yes~e~bad~bad~ok:true\nQ~log.level~debug~e~bad~bad~bad\nQ~name~-~-~-~-~-\nQ~server.nope~-~-~-~-~-\nQ~server.port~-~-~-~-~-\nS~json~7b22726174696f223a20227831222c2022736572766572223a207b22686f7374223a202274727565222c2022706f7274223a20317d2c202266656174757265223a207b2262657461223a202268656c6c6f227d2c2022657874726173223a205b2261222c20312c20747275652c206e756c6c2c207b226b223a202276227d5d7d~server.host=x1;db.pool.size=2.5~APP_EXTRAS_2=-3;APP_EXTRAS_0=yes~log.level=1;server.port=hello;server.host=2.5\nQ~absent.one~-~-~-~-~-\nQ~db.pool.size~2.5~d~bad~ok:2.500000~bad\nQ~extras.0~yes~e~bad~bad~ok:true\nQ~extras.1~1~f~ok:1~ok:1.000000~ok:true\nQ~extras.2~-3~e~ok:-3~ok:-3.000000~bad\nQ~extras.4.k~v~f~bad~bad~bad\nQ~feature.beta~hello~f~bad~bad~bad\nQ~log.level~1~l~ok:1~ok:1.000000~ok:true\nQ~ratio~x1~f~bad~bad~bad\nQ~server.host~2.5~l~bad~ok:2.500000~bad\nQ~server.nope~-~-~-~-~-\nQ~server.port~hello~l~bad~bad~bad\nS~ini~5b6c6f675d0a6c6576656c3d64656275670a~log.json=1;log.level=-3;feature.beta=1;db.pool.size=-3;db.pool.max=2.5~APP_UNKNOWN_KEY=1~log.level=Off\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~2.5~d~bad~ok:2.500000~bad\nQ~db.pool.size~-3~d~ok:-3~ok:-3.000000~bad\nQ~feature.beta~1~d~ok:1~ok:1.000000~ok:true\nQ~log.json~1~d~ok:1~ok:1.000000~ok:true\nQ~log.level~Off~l~bad~bad~ok:false\nQ~server.host~-~-~-~-~-\nQ~server.nope~-~-~-~-~-\nS~json~7b226462223a207b22706f6f6c223a207b2273697a65223a2022302e313235227d7d2c20226e616d65223a20322e357d~log.json=FALSE;name=debug;feature.beta=0;db.pool.size=x1~~name=0;db.pool.size=-3;ratio=yes\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~-~-~-~-~-\nQ~db.pool.size~-3~l~ok:-3~ok:-3.000000~bad\nQ~feature.beta~0~d~ok:0~ok:0.000000~ok:false\nQ~log.json~FALSE~d~bad~bad~ok:false\nQ~name~0~l~ok:0~ok:0.000000~ok:false\nQ~ratio~yes~l~bad~bad~ok:true\nQ~server.nope~-~-~-~-~-\nQ~server.port~-~-~-~-~-\nS~ini~5b64625d0a706f6f6c2e73697a65203d20300a0a5b666561747572655d0a626574613d300a~log.json=true;log.level=0;server.host=2.5;feature.beta=true;server.port=debug;db.pool.max=0.125~APP_UNKNOWN_KEY=-3;APP_LOG_JSON=2.5;APP_DB_POOL_SIZE=-3~log.json=x1;ratio=-3\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~0.125~d~bad~ok:0.125000~bad\nQ~db.pool.size~-3~e~ok:-3~ok:-3.000000~bad\nQ~feature.beta~0~f~ok:0~ok:0.000000~ok:false\nQ~log.json~x1~l~bad~bad~bad\nQ~log.level~0~d~ok:0~ok:0.000000~ok:false\nQ~ratio~-3~l~ok:-3~ok:-3.000000~bad\nQ~server.host~2.5~d~bad~ok:2.500000~bad\nQ~server.nope~-~-~-~-~-\nQ~server.port~debug~d~bad~bad~bad\nS~json~7b0a2020226c6f67223a207b0a20202020226a736f6e223a20222d33220a20207d2c0a202022657874726173223a205b0a202020202261222c0a20202020312c0a20202020747275652c0a202020206e756c6c2c0a202020207b0a202020202020226b223a202276220a202020207d0a20205d0a7d~name=8080;feature.beta=debug;db.pool.max=2.5;ratio=yes~~db.pool.max=2.5;ratio=8080;server.host=0.125\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~2.5~l~bad~ok:2.500000~bad\nQ~extras.0~a~f~bad~bad~bad\nQ~extras.1~1~f~ok:1~ok:1.000000~ok:true\nQ~extras.2~true~f~bad~bad~ok:true\nQ~extras.4.k~v~f~bad~bad~bad\nQ~feature.beta~debug~d~bad~bad~bad\nQ~log.json~-3~f~ok:-3~ok:-3.000000~bad\nQ~name~8080~d~ok:8080~ok:8080.000000~bad\nQ~ratio~8080~l~ok:8080~ok:8080.000000~bad\nQ~server.host~0.125~l~bad~ok:0.125000~bad\nQ~server.nope~-~-~-~-~-\nQ~server.port~-~-~-~-~-\nS~ini~5b64625d0a706f6f6c2e6d61783d64656275670a0a5b6c6f675d0a6c6576656c3d78310a6a736f6e203d20302e3132350a0a5b7365727665725d0a706f7274203d207965730a686f73743d68656c6c6f0a~db.pool.size=1;log.json=FALSE;server.host=0.125;db.pool.max=x1~APP_SERVER_HOST=2.5;APP_DB_POOL_MAX=-3;APP_SERVER_PORT=yes~log.json=8080;server.port=1;ratio=1\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~-3~e~ok:-3~ok:-3.000000~bad\nQ~db.pool.size~1~d~ok:1~ok:1.000000~ok:true\nQ~feature.beta~-~-~-~-~-\nQ~log.json~8080~l~ok:8080~ok:8080.000000~bad\nQ~log.level~x1~f~bad~bad~bad\nQ~ratio~1~l~ok:1~ok:1.000000~ok:true\nQ~server.host~2.5~e~bad~ok:2.500000~bad\nQ~server.nope~-~-~-~-~-\nQ~server.port~1~l~ok:1~ok:1.000000~ok:true\nS~json~7b226e616d65223a20312c2022657874726173223a205b2261222c20312c20747275652c206e756c6c2c207b226b223a202276227d5d7d~ratio=x1;db.pool.size=FALSE;db.pool.max=x1;server.port=hello;log.level=hello~APP_EXTRAS_2=0.125;APP_NAME=-3~db.pool.max=-3;log.level=0;log.json=true\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~-3~l~ok:-3~ok:-3.000000~bad\nQ~db.pool.size~FALSE~d~bad~bad~ok:false\nQ~extras.0~a~f~bad~bad~bad\nQ~extras.1~1~f~ok:1~ok:1.000000~ok:true\nQ~extras.2~0.125~e~bad~ok:0.125000~bad\nQ~extras.4.k~v~f~bad~bad~bad\nQ~log.json~true~l~bad~bad~ok:true\nQ~log.level~0~l~ok:0~ok:0.000000~ok:false\nQ~name~-3~e~ok:-3~ok:-3.000000~bad\nQ~ratio~x1~d~bad~bad~bad\nQ~server.nope~-~-~-~-~-\nQ~server.port~hello~d~bad~bad~bad\nS~ini~5b64625d0a706f6f6c2e6d61783d302e3132350a0a5b6c6f675d0a6c6576656c203d207965730a0a5b7365727665725d0a706f72743d310a0a5b666561747572655d0a62657461203d2064656275670a0a~db.pool.size=x1;log.json=0.125;log.level=hello;server.host=FALSE;db.pool.max=2.5;feature.beta=yes~APP_UNKNOWN_KEY=yes~\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~0.125~f~bad~ok:0.125000~bad\nQ~db.pool.size~x1~d~bad~bad~bad\nQ~feature.beta~debug~f~bad~bad~bad\nQ~log.json~0.125~d~bad~ok:0.125000~bad\nQ~log.level~yes~f~bad~bad~ok:true\nQ~name~-~-~-~-~-\nQ~ratio~-~-~-~-~-\nQ~server.host~FALSE~d~bad~bad~ok:false\nQ~server.nope~-~-~-~-~-\nQ~server.port~1~f~ok:1~ok:1.000000~ok:true\nS~json~7b226c6f67223a207b226a736f6e223a20226465627567227d2c2022736572766572223a207b22686f7374223a202268656c6c6f227d2c2022726174696f223a202231227d~log.json=2.5;log.level=FALSE;feature.beta=-3;db.pool.size=1;server.port=Off;ratio=FALSE~APP_LOG_LEVEL=8080~db.pool.max=hello;extra.flag=FALSE;log.json=FALSE\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~hello~l~bad~bad~bad\nQ~db.pool.size~1~d~ok:1~ok:1.000000~ok:true\nQ~extra.flag~FALSE~l~bad~bad~ok:false\nQ~feature.beta~-3~d~ok:-3~ok:-3.000000~bad\nQ~log.json~FALSE~l~bad~bad~ok:false\nQ~log.level~8080~e~ok:8080~ok:8080.000000~bad\nQ~ratio~1~f~ok:1~ok:1.000000~ok:true\nQ~server.host~hello~f~bad~bad~bad\nQ~server.nope~-~-~-~-~-\nQ~server.port~Off~d~bad~bad~ok:false\nS~ini~5b7365727665725d0a686f7374203d2078310a706f72743d64656275670a0a5b6c6f675d0a6a736f6e203d20300a6c6576656c203d20383038300a0a5b64625d0a706f6f6c2e6d61783d7965730a~server.port=debug;log.level=1;db.pool.size=1~APP_SERVER_PORT=0.125;APP_DB_POOL_SIZE=2.5~log.json=yes\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~yes~f~bad~bad~ok:true\nQ~db.pool.size~2.5~e~bad~ok:2.500000~bad\nQ~log.json~yes~l~bad~bad~ok:true\nQ~log.level~8080~f~ok:8080~ok:8080.000000~bad\nQ~server.host~x1~f~bad~bad~bad\nQ~server.nope~-~-~-~-~-\nQ~server.port~0.125~e~bad~ok:0.125000~bad\nS~json~7b0a2020226e616d65223a20224f6666222c0a2020226c6f67223a207b0a20202020226a736f6e223a202d330a20207d2c0a20202266656174757265223a207b0a202020202262657461223a20322e350a20207d0a7d~log.json=hello;server.port=debug;name=true;server.host=hello;feature.beta=0;db.pool.max=-3~APP_LOG_JSON=8080;APP_DB_POOL_MAX=hello;APP_FEATURE_BETA=0.125;APP_SERVER_HOST=true~server.port=Off;log.json=0.125\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~hello~e~bad~bad~bad\nQ~feature.beta~0.125~e~bad~ok:0.125000~bad\nQ~log.json~0.125~l~bad~ok:0.125000~bad\nQ~name~Off~f~bad~bad~ok:false\nQ~server.host~true~e~bad~bad~ok:true\nQ~server.nope~-~-~-~-~-\nQ~server.port~Off~l~bad~bad~ok:false\nS~ini~~log.json=Off;db.pool.size=FALSE;server.port=yes~~\nQ~absent.one~-~-~-~-~-\nQ~db.pool.size~FALSE~d~bad~bad~ok:false\nQ~log.json~Off~d~bad~bad~ok:false\nQ~log.level~-~-~-~-~-\nQ~name~-~-~-~-~-\nQ~server.host~-~-~-~-~-\nQ~server.nope~-~-~-~-~-\nQ~server.port~yes~d~bad~bad~ok:true\nS~json~7b0a2020226462223a207b0a2020202022706f6f6c223a207b0a2020202020202273697a65223a20383038300a202020207d0a20207d2c0a2020226e616d65223a20302c0a202022736572766572223a207b0a2020202022686f7374223a2022302e313235220a20207d2c0a2020226c6f67223a207b0a20202020226a736f6e223a20224f6666220a20207d0a7d~log.level=1;name=-3;db.pool.max=1~~ratio=hello\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~1~d~ok:1~ok:1.000000~ok:true\nQ~db.pool.size~8080~f~ok:8080~ok:8080.000000~bad\nQ~log.json~Off~f~bad~bad~ok:false\nQ~log.level~1~d~ok:1~ok:1.000000~ok:true\nQ~name~0~f~ok:0~ok:0.000000~ok:false\nQ~ratio~hello~l~bad~bad~bad\nQ~server.host~0.125~f~bad~ok:0.125000~bad\nQ~server.nope~-~-~-~-~-\nS~ini~5b666561747572655d0a62657461203d2046414c53450a0a5b7365727665725d0a706f7274203d20322e350a0a5b6c6f675d0a6a736f6e3d64656275670a0a~db.pool.max=x1;db.pool.size=hello;log.level=yes;server.port=true;server.host=0;feature.beta=0~APP_DB_POOL_MAX=Off;APP_SERVER_HOST=0~log.level=FALSE;extra.flag=-3;ratio=hello\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~Off~e~bad~bad~ok:false\nQ~db.pool.size~hello~d~bad~bad~bad\nQ~extra.flag~-3~l~ok:-3~ok:-3.000000~bad\nQ~feature.beta~FALSE~f~bad~bad~ok:false\nQ~log.json~debug~f~bad~bad~bad\nQ~log.level~FALSE~l~bad~bad~ok:false\nQ~ratio~hello~l~bad~bad~bad\nQ~server.host~0~e~ok:0~ok:0.000000~ok:false\nQ~server.nope~-~-~-~-~-\nQ~server.port~2.5~f~bad~ok:2.500000~bad\nS~json~7b22657874726173223a205b2261222c20312c20747275652c206e756c6c2c207b226b223a202276227d5d7d~db.pool.max=hello;log.level=FALSE;ratio=0.125~APP_RATIO=0.125;APP_EXTRAS_1=2.5;APP_EXTRAS_2=0.125;APP_DB_POOL_MAX=yes~ratio=0\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~yes~e~bad~bad~ok:true\nQ~extras.0~a~f~bad~bad~bad\nQ~extras.1~2.5~e~bad~ok:2.500000~bad\nQ~extras.2~0.125~e~bad~ok:0.125000~bad\nQ~extras.4.k~v~f~bad~bad~bad\nQ~feature.beta~-~-~-~-~-\nQ~log.level~FALSE~d~bad~bad~ok:false\nQ~ratio~0~l~ok:0~ok:0.000000~ok:false\nQ~server.host~-~-~-~-~-\nQ~server.nope~-~-~-~-~-\nS~ini~5b7365727665725d0a706f72743d302e3132350a0a5b6c6f675d0a6a736f6e203d20302e3132350a0a5b64625d0a706f6f6c2e6d61783d78310a706f6f6c2e73697a65203d20383038300a0a5b666561747572655d0a62657461203d2078310a~db.pool.max=0.125;log.json=Off;server.port=1;server.host=8080~APP_UNKNOWN_KEY=FALSE;APP_DB_POOL_SIZE=debug~\nQ~absent.one~-~-~-~-~-\nQ~db.pool.max~x1~f~bad~bad~bad\nQ~db.pool.size~debug~e~bad~bad~bad\nQ~feature.beta~x1~f~bad~bad~bad\nQ~log.json~0.125~f~bad~ok:0.125000~bad\nQ~log.level~-~-~-~-~-\nQ~server.host~8080~d~ok:8080~ok:8080.000000~bad\nQ~server.nope~-~-~-~-~-\nQ~server.port~0.125~f~bad~ok:0.125000~bad"
}

fn nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(a: *mem.Arena, h: str) -> str {
    let (out, e) = mem.alloc[u8](a, h.len / 2usize + 1usize)
    if e != ok { os.exit(90i32) }
    var i = 0usize
    while i + 1usize < h.len {
        out[i / 2usize] = (nibble(h[i]) << 4u8) | nibble(h[i + 1usize])
        i += 2usize
    }
    ret out[0..h.len / 2usize]
}

// `k=v;k=v` into pieces (borrowing `s`).
fn pieces(a: *mem.Arena, s: str) -> []str {
    if s.len == 0usize {
        let (none, ne) = mem.alloc[str](a, 1usize)
        if ne != ok { os.exit(91i32) }
        ret none[0..0]
    }
    let (out, e) = mem.alloc[str](a, str.count(s, ";") + 1usize)
    if e != ok { os.exit(91i32) }
    var n = 0usize
    var rest = s
    while true {
        let (head, tail, found) = str.split_once(rest, ";")
        if !found {
            out[n] = rest
            n += 1usize
            break
        }
        out[n] = head
        n += 1usize
        rest = tail
    }
    ret out[0..n]
}

fn layer_letter(l: config.Layer) -> str {
    if l == config.Layer.Default { ret "d" }
    if l == config.Layer.File { ret "f" }
    if l == config.Layer.Env { ret "e" }
    ret "l"
}

fn typed_i(c: *const config.Config, key: str, a: *mem.Arena) -> str {
    let (v, e) = config.get_i64(c, key)
    if e != ok { ret "bad" }
    let (b0, be) = str.builder(a, 40usize)
    if be != ok { os.exit(92i32) }
    var b = b0
    if str.push(&b, "ok:") != ok || str.push_i64(&b, v) != ok { os.exit(92i32) }
    ret str.done(&b)
}

fn typed_f(c: *const config.Config, key: str, a: *mem.Arena) -> str {
    let (v, e) = config.get_f64(c, key)
    if e != ok { ret "bad" }
    let (b0, be) = str.builder(a, 64usize)
    if be != ok { os.exit(93i32) }
    var b = b0
    if str.push(&b, "ok:") != ok || str.push_f64_fixed(&b, v, 6u8) != ok { os.exit(93i32) }
    ret str.done(&b)
}

fn typed_b(c: *const config.Config, key: str) -> str {
    let (v, e) = config.get_bool(c, key)
    if e != ok { ret "bad" }
    if v { ret "ok:true" }
    ret "ok:false"
}

fn check_vectors(a: *mem.Arena) -> i32 {
    var lines = str.lines(vectors())
    var cfg: config.Config = zero
    var scenarios = 0i32
    var queries = 0i32
    while true {
        let (line, more) = str.split_next(&lines)
        if !more { break }
        if line.len == 0usize { continue }
        let (kind, rest, found) = str.split_once(line, "~")
        if !found { ret 10i32 }
        if str.eq(kind, "S") {
            let (fmt, r1, g1) = str.split_once(rest, "~")
            let (file_hex, r2, g2) = str.split_once(r1, "~")
            let (defaults, r3, g3) = str.split_once(r2, "~")
            let (env, flags, g4) = str.split_once(r3, "~")
            if !g1 || !g2 || !g3 || !g4 { ret 11i32 }
            let (made, me) = config.config(a, 96usize)
            if me != ok { ret 12i32 }
            cfg = made
            if config.layer_defaults(&cfg, pieces(a, defaults)) != ok { ret 13i32 }
            let file_text = unhex(a, file_hex)
            if str.eq(fmt, "json") {
                if config.layer_json(a, &cfg, file_text) != ok { ret 14i32 }
            } else {
                if config.layer_ini(a, &cfg, file_text) != ok { ret 15i32 }
            }
            if config.layer_env(a, &cfg, "APP_", pieces(a, env)) != ok { ret 16i32 }
            // Flags as a parsed command line would deliver them: each a one-string option.
            let flag_list = pieces(a, flags)
            let (options, oe) = mem.alloc[cli.ParsedOption](a, flag_list.len + 1usize)
            if oe != ok { ret 17i32 }
            var i = 0usize
            while i < flag_list.len {
                let (k, v, kv) = str.split_once(flag_list[i], "=")
                let (values, ve) = mem.alloc[cli.Value](a, 1usize)
                if !kv || ve != ok { ret 18i32 }
                values[0] = cli.Value{ String: v }
                options[i] = cli.ParsedOption { name: k, values: values }
                i += 1usize
            }
            let result = cli.Result { command: "", options: options[0..flag_list.len], positionals: zero }
            if config.layer_flags(a, &cfg, &result) != ok { ret 19i32 }
            scenarios += 1i32
        } else if str.eq(kind, "Q") {
            let (key, r1, g1) = str.split_once(rest, "~")
            let (want_value, r2, g2) = str.split_once(r1, "~")
            let (want_layer, r3, g3) = str.split_once(r2, "~")
            let (want_i, r4, g4) = str.split_once(r3, "~")
            let (want_f, want_b, g5) = str.split_once(r4, "~")
            if !g1 || !g2 || !g3 || !g4 || !g5 { ret 20i32 }
            let (value, present) = config.get_str(&cfg, key)
            if !present {
                if !str.eq(want_value, "-") { ret 100i32 + queries }
                let (zero_value, missing) = config.get_i64(&cfg, key)
                if missing != config.Missing { ret 21i32 }
            } else {
                if !str.eq(value, want_value) { ret 100i32 + queries }
                let (layer, lp) = config.layer_of(&cfg, key)
                if !lp || !str.eq(layer_letter(layer), want_layer) { ret 600i32 + queries }
                if !str.eq(typed_i(&cfg, key, a), want_i) { ret 1100i32 + queries }
                if !str.eq(typed_f(&cfg, key, a), want_f) { ret 1600i32 + queries }
                if !str.eq(typed_b(&cfg, key), want_b) { ret 2100i32 + queries }
            }
            queries += 1i32
        }
    }
    if scenarios != 40i32 || queries != 403i32 { ret 22i32 }
    ret 0i32
}

fn write(a: *mem.Arena, path: str, text: str) -> bool {
    ret fs.write_file(a, path, text) == ok
}

fn cleanup(a: *mem.Arena) {
    let (entries, e) = os.readdir(a, "np-config")
    if e != ok { ret }
    var i = 0usize
    while i < entries.len {
        let (path, pe) = str.concat(a, "np-config/", entries[i].name)
        let r = fs.remove_file(a, path)
        i += 1usize
    }
    let d = fs.remove_dir(a, "np-config")
}

fn value_is(c: *const config.Config, key: str, want: str) -> bool {
    let (v, found) = config.get_str(c, key)
    ret found && str.eq(v, want)
}

fn check_reload(a: *mem.Arena) -> i32 {
    cleanup(a)
    if fs.make_dirs(a, "np-config") != ok { ret 30i32 }
    if !write(a, "np-config/app.ini", "[server]\nport = 80\nhost = alpha\n") { ret 31i32 }
    let (cfg0, ce) = config.config(a, 32usize)
    if ce != ok { ret 32i32 }
    var cfg = cfg0
    var defaults: [2]str = zero
    defaults[0] = "server.port=1"
    defaults[1] = "log.level=info"
    if config.layer_defaults(&cfg, defaults[0..]) != ok { ret 33i32 }
    let (n0, e0) = config.reload(a, &cfg, "np-config/app.ini", config.Format.Ini)
    if e0 != ok { ret 34i32 }
    // port 1 -> 80, host new: two keys changed.
    if n0 != 2usize || !value_is(&cfg, "server.port", "80") || !value_is(&cfg, "server.host", "alpha") { ret 35i32 }
    // The second file drops host, changes port, adds log.level over its default.
    if !write(a, "np-config/app.ini", "[server]\nport = 81\n[log]\nlevel = warn\n") { ret 36i32 }
    let (n1, e1) = config.reload(a, &cfg, "np-config/app.ini", config.Format.Ini)
    if e1 != ok || n1 != 3usize { ret 37i32 }
    if !value_is(&cfg, "server.port", "81") || !value_is(&cfg, "log.level", "warn") { ret 38i32 }
    let (host, host_found) = config.get_str(&cfg, "server.host")
    if host_found { ret 39i32 }
    // A flag outranks the file: reloading a changed port does not change what the program sees.
    if config.set(&cfg, config.Layer.Flag, "server.port", "9") != ok { ret 40i32 }
    if !write(a, "np-config/app.ini", "[server]\nport = 82\n[log]\nlevel = warn\n") { ret 41i32 }
    let (n2, e2) = config.reload(a, &cfg, "np-config/app.ini", config.Format.Ini)
    if e2 != ok || n2 != 0usize || !value_is(&cfg, "server.port", "9") { ret 42i32 }
    // A broken file keeps the previous values; a missing one is an error as well.
    if !write(a, "np-config/app.ini", "[server\nport = 1\n") { ret 43i32 }
    let (n3, e3) = config.reload(a, &cfg, "np-config/app.ini", config.Format.Ini)
    if e3 != config.Invalid || !value_is(&cfg, "log.level", "warn") { ret 44i32 }
    let (n4, e4) = config.reload(a, &cfg, "np-config/missing.ini", config.Format.Ini)
    if e4 == ok || !value_is(&cfg, "log.level", "warn") { ret 45i32 }
    // JSON, with typed reads off the file layer.
    if !write(a, "np-config/app.json", "{\"limits\": {\"rate\": 2.5, \"burst\": 10}, \"on\": true, \"tags\": [\"x\", \"y\"]}") { ret 46i32 }
    let (n5, e5) = config.reload(a, &cfg, "np-config/app.json", config.Format.Json)
    if e5 != ok || n5 != 6usize { ret 47i32 }
    let (rate, re) = config.get_f64(&cfg, "limits.rate")
    let (burst, be) = config.get_u64(&cfg, "limits.burst")
    let (on, oe) = config.get_bool(&cfg, "on")
    if re != ok || rate != 2.5f64 || be != ok || burst != 10u64 || oe != ok || !on { ret 48i32 }
    if !value_is(&cfg, "tags.1", "y") { ret 49i32 }
    // split_path.
    let (d1, b1) = config.split_path("a/b/c.ini")
    let (d2, b2) = config.split_path("c.ini")
    let (d3, b3) = config.split_path("/c.ini")
    let (d4, b4) = config.split_path("a\\b.ini")
    if !str.eq(d1, "a/b") || !str.eq(b1, "c.ini") || !str.eq(d2, ".") || !str.eq(b2, "c.ini") { ret 50i32 }
    if !str.eq(d3, "/") || !str.eq(b3, "c.ini") || !str.eq(d4, "a") || !str.eq(b4, "b.ini") { ret 51i32 }
    ret 0i32
}

fn check_flags(a: *mem.Arena) -> i32 {
    // A real parse: typed options land in the flag layer as text.
    var options: [4]cli.Option = zero
    options[0] = cli.Option { long: "server.port", short: 0u8, kind: cli.ValueKind.U64, required: false, repeated: false, env: "", help: "" }
    options[1] = cli.Option { long: "verbose", short: 118u8, kind: cli.ValueKind.Bool, required: false, repeated: false, env: "", help: "" }
    options[2] = cli.Option { long: "ratio", short: 0u8, kind: cli.ValueKind.F64, required: false, repeated: false, env: "", help: "" }
    options[3] = cli.Option { long: "name", short: 0u8, kind: cli.ValueKind.String, required: false, repeated: true, env: "", help: "" }
    let command = cli.Command { name: "app", help: "", options: options[0..], subcommands: zero }
    var args: [6]str = zero
    args[0] = "--server.port=8081"
    args[1] = "-v"
    args[2] = "--ratio"
    args[3] = "0.5"
    args[4] = "--name=a"
    args[5] = "--name=b"
    let (result, pe) = cli.parse(a, &command, args[0..])
    if pe != ok { ret 60i32 }
    let (c0, ce) = config.config(a, 16usize)
    if ce != ok { ret 61i32 }
    var cfg = c0
    var defaults: [2]str = zero
    defaults[0] = "server.port=80"
    defaults[1] = "ratio=1"
    if config.layer_defaults(&cfg, defaults[0..]) != ok { ret 62i32 }
    if config.layer_flags(a, &cfg, &result) != ok { ret 63i32 }
    if !value_is(&cfg, "server.port", "8081") || !value_is(&cfg, "verbose", "true") || !value_is(&cfg, "name", "b") { ret 64i32 }
    let (r, re) = config.get_f64(&cfg, "ratio")
    if re != ok || r != 0.5f64 { ret 65i32 }
    let (layer, lf) = config.layer_of(&cfg, "ratio")
    if !lf || layer != config.Layer.Flag { ret 66i32 }
    // The process environment for known keys: PATH is almost surely set, and an unknown name is not read.
    var more: [1]str = zero
    more[0] = "path=unset"
    if config.layer_defaults(&cfg, more[0..]) != ok { ret 67i32 }
    if config.layer_process_env(a, &cfg, "") != ok { ret 68i32 }
    ret 0i32
}

// `watch.read` blocks until the host delivers an event. A file system that delivers none (inotify on a Windows
// drive under WSL) would leave the run waiting for ever, so a thread with a poller of its own ends it with 99.
type Watchdog = struct { seconds: i64 }

fn watchdog(g: *Watchdog) {
    var backing: [4096]u8 = zero
    var arena = mem.arena_from(backing[..])
    let (poller, open_error) = os.poller_open(&arena)
    if open_error != ok { os.exit(98i32) }
    defer let _ = os.poller_close(poller)
    var none: [1]os.PollEvent = zero
    let (woken, wait_error) = os.poller_wait(poller, none[..], g.seconds * 1000000000i64)
    os.exit(99i32)
}

fn check_watch(a: *mem.Arena) -> i32 {
    let (guards, guard_error) = mem.alloc[Watchdog](a, 1usize)
    if guard_error != ok { ret 69i32 }
    guards[0usize] = Watchdog { seconds: 120i64 }
    let (sentinel, sentinel_error) = thread.spawn[Watchdog](watchdog, &guards[0usize], 0usize)
    if sentinel_error != ok { ret 69i32 }
    let sentinel_detached = thread.detach(sentinel)
    if !write(a, "np-config/live.json", "{\"mode\": \"one\"}") { ret 70i32 }
    let (c0, ce) = config.config(a, 16usize)
    if ce != ok { ret 71i32 }
    var cfg = c0
    let (n0, e0) = config.reload(a, &cfg, "np-config/live.json", config.Format.Json)
    if e0 != ok || n0 != 1usize || !value_is(&cfg, "mode", "one") { ret 72i32 }
    let (dir, base) = config.split_path("np-config/live.json")
    let (w, we) = watch.open(a, dir, false)
    if we != ok { ret 73i32 }
    // Three rapid saves; the watcher answers once and the file layer holds the last.
    if !write(a, "np-config/live.json", "{\"mode\": \"two\"}") { ret 74i32 }
    if !write(a, "np-config/live.json", "{\"mode\": \"three\"}") { ret 75i32 }
    if !write(a, "np-config/live.json", "{\"mode\": \"four\"}") { ret 76i32 }
    let (matched, changed, pe) = config.watch_poll(a, w, &cfg, dir, base, "np-config/live.json", config.Format.Json)
    let closed = watch.close(w)
    if pe != ok { ret 77i32 }
    if matched < 1usize || changed != 1usize { ret 78i32 }
    if !value_is(&cfg, "mode", "four") { ret 79i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var code = check_vectors(a)
    if code == 0i32 { code = check_reload(a) }
    if code == 0i32 { code = check_flags(a) }
    if code == 0i32 { code = check_watch(a) }
    cleanup(a)
    if code != 0i32 { os.exit(code) }
    let e = io.print("cli config ok")
    ret ok
}
