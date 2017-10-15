var fs = require('fs');

var url = "https://"+process.env.CI_DB_INFO+"@"+process.env.CI_DB_HOST;
var dbname = process.env.CI_DB_NAME;
var key = process.env.CI_DB_KEY;


console.log("update-couchdb-doc: DB '"+dbname+"', key: "+key);
var server = require('nano')(url);
var db = server.db.use(dbname);
var buildkey = key+':'+process.env.TRAVIS_JOB_NUMBER;

var results = JSON.parse(fs.readFileSync(process.env.CI_BUILD_RESULTS));
var build = {
  "env": {},
  "stats": {
    "total": results.stats.asserts,
    "passed": results.stats.passes,
    "failed": results.stats.failures
  },
  "tests": results.asserts
};
for (k in process.env) {
  if (k.substr(0, 6) == 'TRAVIS') {
    build.env[k] = process.env[k];
  }
}

// Store current build
db.insert(build, buildkey);

// Set latest build info
db.get(key, function( err, buildlog, headers ) {

  if (!buildlog) {
    buildlog = {"builds": {}};
  }
  buildlog.builds[process.env.TRAVIS_JOB_NUMBER] = {
    "stats": build.stats,
    "scm": {
      "commits": process.env.TRAVIS_COMMIT_RANGE,
      "branch": process.env.TRAVIS_BRANCH
    }
  };

  db.insert( buildlog, key );
});

// Id: node-sitefile/0.0.7-dev tools/update-couchdb-testlog.js
// From: script-mpe/0.0.4-dev tools/update-couchdb-testlog.js
