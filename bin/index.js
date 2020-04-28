const fs = require('fs');
const path = require('path');
const challk = require('chalk');
const { exec } = require('node-exec-promise');
const rimraf = require("rimraf");
const shellescape = require('shell-escape');
const zip = require('adm-zip');

const binaryDirName = 'binary';

const dirName = path.normalize(process.argv[2]).replace('~', process.env['HOME']);

if (!fs.existsSync(dirName)) {
    console.log(challk.red(`${dirName} is not exits!`));
    process.exit(1);
}

if (!fs.lstatSync(dirName).isDirectory) {
    console.log(challk.red(`${dirName} is not a dir!`));
    process.exit(1);
}

rimraf.sync(binaryDirName);
fs.mkdirSync(binaryDirName);

// 查找目录内部带有 ipa 的文件
const ipaList = fs.readdirSync(dirName).filter(file => path.extname(file) === '.ipa').map(file => path.join(dirName, file));

(async function() {
    const result = await Promise.all(ipaList.map(async (ipaPath) => {
        const ipaName = path.basename(ipaPath);
        const unzipCommand = shellescape(['unzip', '-l', ipaPath]);
        // 先直接 unzip -l 看一下是否包含 swift，如果包含，直接记录下来
        const zipFrameworkDetails = (await exec(`${unzipCommand} | grep 'Frameworks' || echo ""`)).stdout.split("\n").map(line => line.split(' ').pop()).filter(line => line.length > 0);
        const zip = new zip(ipaPath);
        const zipEntries = zip.getEntries();
        const swiftLibDetails = zipEntries.filter(entry => entry.toString().includes('libswift'));
        if (swiftLibDetails.length > 0) {
            return {
                name: ipaName,
                result: true,
                details: swiftLibDetails,
            };
        }
        // 如果不包含，单纯解压可执行文件，然后 utool 查看是否链接到 swift
        const appPath = (await exec(`${unzipCommand} | grep '.app/' | head`)).stdout.split("\n").map(line => line.split(' ').pop())[0];
        const binaryName = path.basename(appPath.split('/')[1], '.app');
        const binaryPath = `Payload/${binaryName}.app/${binaryName}`;
        // 仅仅把二进制解压出来
        const unzipComand = shellescape(['unzip', ipaPath, binaryPath, '-d', binaryDirName]);
        await exec(unzipComand)
        const otoolDetails = (await exec(`otool -L ${binaryDirName}/${binaryPath} | grep libswift || echo ''`)).stdout.split("\n").filter(line => line.length > 0);
        return {
            name: ipaName,
            result: otoolDetails.length > 0,
            details: otoolDetails || [],
        }
    }));

    console.log(JSON.stringify(result));
})();

