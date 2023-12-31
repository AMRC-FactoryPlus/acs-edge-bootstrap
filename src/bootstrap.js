require('dotenv-defaults').config();

const axios     = require('axios').default;
const os        = require('os');
const fs        = require('fs/promises');
const { Agent } = require('https');

const GSS = require('gssapi.js');

run(process.argv.slice(2));

async function run (argv) {
    const [edge, template] = argv;

    const name = os.hostname();
    console.log(`Naming this cluster ${name}`);

    // Read the kubeseal cert from the file
    console.log('Reading kubeseal cert from file...');
    const kubeseal_cert = await fs.readFile("install/kubesealCert.pem", 
        { encoding: "utf-8" });
    console.log('Kubeseal cert read successfully.');

    const instance = axios.create();

    // Register the cluster with the API
    console.log(`Contacting Edge Deployment at ${edge}`);

    // Make the request to the API to register the cluster
    console.log('Registering cluster with API...');
    let e = await instance.post(`${edge}/v1/cluster`, {
        name, kubeseal_cert, template,
    }, {
        headers: {
            'Authorization': `Negotiate ${await getSingleUseToken(edge)}`
        }
    });

    // Set the UUID and flux URL
    const uuid = e.data.uuid;
    const flux = e.data.flux;

    if (!uuid) {
        throw new Error('UUID not set');
    }

    if (!flux) {
        throw new Error('flux not set');
    }

    // Poll the API to check if the cluster has been registered
    await poll(async () => 
        instance.get(`${edge}/v1/cluster/${uuid}/status`, {
            headers: {
                'Authorization': `Negotiate ${await getSingleUseToken(edge)}`
            }
        })
        .then(validateResponse));
    console.log("Cluster is set up and ready to deploy");

    console.log("Fetching temporary token for flux repo...")
    let git_tok_url = new URL("/token", flux).toString();
    let git_res = await instance.post(git_tok_url, {}, {
        headers: {
            'Authorization': `Negotiate ${await getSingleUseToken(git_tok_url)}`,
        },
    });
    if (git_res.status != 200)
        throw `Can't fetch a temporary token for the git repo: ${git_res.status}`;
    let git_tok = git_res.data.token;

    await fs.writeFile("install/cluster-info.sh", `
CLUSTER_NAME="${name}"
FLUX_URL="${flux}"
FLUX_TOKEN="${git_tok}"
`);
}

/**
 * Poll the API to check if the cluster has been registered
 * @param fn
 * @returns {Promise<void | unknown>}
 */
function poll (fn) {
    console.log('Waiting for confirmation that cluster has been registered...');

    return Promise.resolve()
                  .then(fn)
                  .catch(function retry () {
                      return sleep(5000).then(fn).catch(retry);
                  });
}

/**
 * Validates the response from the API
 * @param res
 */
function validateResponse (res) {
    // If the response is not 200 or the ready flag is not true then fail
    if (!res.data || res.status !== 200 || res.data.ready !== true) throw res;
}

/**
 * A helper function to sleep for a given number of milliseconds
 * @param ms
 * @returns {Promise<unknown>}
 */
function sleep (ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function getSingleUseToken (url) {
    const host = new URL(url).hostname;
    const ctx = GSS.createClientContext({ server: `HTTP@${host}` });
    const tok = await GSS.initSecContext(ctx);
    const tok64 = tok.toString('base64');
    return tok64;
}
