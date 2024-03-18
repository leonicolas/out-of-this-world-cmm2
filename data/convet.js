const fs = require("fs");
const ootwdata = require("./ootwdemo");
const uncompress = require("./decrunch").uncompress;

for (let key of Object.keys(ootwdata)) {
    const prefix = key.slice(0, 4);
    const num = key.slice(4);
    if (prefix === "data") {
        console.log("Processing", key);
        const file = fs.openSync(`./data/${key}.bin`, "w");
        fs.writeSync(file, load(ootwdata[key], ootwdata[`size${num}`]));
        fs.closeSync(file);
    }
}
console.log("Processing complete!!!");

function load( data, size ) {
	data = atob( data );
	if ( data.length != size ) {
		var buf = uncompress(data);
		console.assert( buf.length == size );
		return buf;
	}
	var buf = new Uint8Array( size );
	for ( var i = 0; i < data.length; ++i ) {
		buf[ i ] = data.charCodeAt( i ) & 0xff;
	}
	return buf;
}
