var redis = require("redis"),
    client = redis.createClient(
	6379, 'testaleck.dov1pm.0001.usw2.cache.amazonaws.com');

// if you'd like to select database 3, instead of 0 (default), call
// client.select(3, function() { /* ... */ });
client.on("error", function (err) {
    console.log("Error " + err);
});
var lineReader = require('readline').createInterface({
  input: require('fs').createReadStream('cmudict.txt')
});

lineReader.on('line', function (line) {
    line = line.toLowerCase()
	.replace(/[0-9]/g, '')
	.split("  ")
    var word = line[0]
    var pronounciation = line[1]
//    console.log({word, pronounciation})
    client.set(pronounciation, JSON.stringify([word]), redis.print);
    client.get(word, (err, reply) =>
	       console.log({reply}))
});

/*
client.on("error", function (err) {
    console.log("Error " + err);
});
 

client.hset("hash key", "hashtest 1", "some value", redis.print);
client.hset(["hash key", "hashtest 2", "some other value"], redis.print);
client.hkeys("hash key", function (err, replies) {
    console.log(replies.length + " replies:");
    replies.forEach(function (reply, i) {
        console.log("    " + i + ": " + reply);
    });
    client.quit();
});

*/
