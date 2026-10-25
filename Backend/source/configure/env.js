const {pool, types} = require('pg')
require('dotenv').config({path:path.join(__dirname,'../../.env'), quiet:true });

const reqruired = [
    'DATABASE_URL',
    'JWT_ACCESS_SECRET',
    'JWT_REFRESH_SECRET',
    'ENCRYPTION_KEY',
    'TICKET_SIGNING_SECRET',
];

const  missing =  reqruired.filter((key)=> !process.env[key]);
if(missing.length) {
    console.log
}