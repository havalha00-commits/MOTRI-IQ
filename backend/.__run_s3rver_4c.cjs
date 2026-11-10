const S3rver = require('s3rver');
const s = new S3rver({ port:4566, address:'127.0.0.1', silent:true, directory:'C:/MOTRI-IQ-TEST/s3-data', configureBuckets:[{name:'cars'}] });
s.run().then(()=>{ process.stdout.write('ready\n'); }).catch(e=>{ console.error(e&&e.stack||e); process.exit(1); });
process.on('SIGTERM',()=>s.close().finally(()=>process.exit(0)));
