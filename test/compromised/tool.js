const { ethers } = require("ethers");

const data = [
    '4d 48 67 33 5a 44 45 31 59 6d 4a 68 4d 6a 5a 6a 4e 54 49 7a 4e 6a 67 7a 59 6d 5a 6a 4d 32 52 6a 4e 32 4e 6b 59 7a 56 6b 4d 57 49 34 59 54 49 33 4e 44 51 30 4e 44 63 31 4f 54 64 6a 5a 6a 52 6b 59 54 45 33 4d 44 56 6a 5a 6a 5a 6a 4f 54 6b 7a 4d 44 59 7a 4e 7a 51 30',
    '4d 48 67 32 4f 47 4a 6b 4d 44 49 77 59 57 51 78 4f 44 5a 69 4e 6a 51 33 59 54 59 35 4d 57 4d 32 59 54 56 6a 4d 47 4d 78 4e 54 49 35 5a 6a 49 78 5a 57 4e 6b 4d 44 6c 6b 59 32 4d 30 4e 54 49 30 4d 54 51 77 4d 6d 46 6a 4e 6a 42 69 59 54 4d 33 4e 32 4d 30 4d 54 55 35',
]

// // 方法1
// function hexToAscii(hex) {
//     let ascii = '';
//     for (let i = 0; i < hex.length; i += 2) {
//         ascii += String.fromCharCode(parseInt(hex.substr(i, 2), 16));
//     }
//     return ascii;
// }

// function decodeBase64(base64Str) {
//     // Decode Base64 to ASCII
//     return atob(base64Str);
// }

// data.forEach(item => {
//     hexStr = item.split(` `).join(``).toString()
//     const asciiStr = hexToAscii(hexStr);
//     const decodedStr = decodeBase64(asciiStr);
//     const privateKey = decodedStr;
//     console.log("Private Key:", privateKey);
//     // Create a wallet instance from the private key
//     const wallet = new ethers.Wallet(privateKey);
//     // Get the public key
//     const address = wallet.address;
//     console.log("Public Key:", address);
// });


data.forEach(item => {
    const byteArray = Uint8Array.from(item.split(' '), v => parseInt(v, 16));
    const decoder = new TextDecoder();
    const base64String = decoder.decode(byteArray);
    // Decode Base64 to ASCII
    const privateKey = atob(base64String);   
    console.log("Private Key:", privateKey);
    const wallet = new ethers.Wallet(privateKey);
    console.log("Public Key:", wallet.address);
});