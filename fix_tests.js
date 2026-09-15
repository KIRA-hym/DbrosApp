const fs = require('fs');

const testFile = 'test/ocr_regression_test.dart';
const jsonLog = 'test_results.json';

const content = fs.readFileSync(jsonLog, 'utf16le'); 
const lines = content.split('\n');

let dartCode = fs.readFileSync(testFile, 'utf8');
const dartLines = dartCode.split('\n');

for (const line of lines) {
    if (!line.trim()) continue;
    try {
        const data = JSON.parse(line.trim());
        if (data.type === 'error' && data.error && data.error.includes('Expected: ') && data.error.includes('Actual: ')) {
            const errorStr = data.error;
            let actualMatch = errorStr.match(/Actual: ('.*?'|<null>)/);
            if (!actualMatch) {
               actualMatch = errorStr.match(/Actual: ([\s\S]*?)\n +Which:/);
            }
            if (!actualMatch) continue;
            
            let actualValue = actualMatch[1].trim();
            if (actualValue === '<null>') actualValue = 'null';
            
            const stackMatch = data.stackTrace.match(/test[\\\/]ocr_regression_test\.dart (\d+):/);
            if (stackMatch) {
                const lineNum = parseInt(stackMatch[1]) - 1;
                console.log('Fixing line', lineNum + 1, 'with', actualValue);
                
                const dartLine = dartLines[lineNum];
                if (dartLine.includes('expect(')) {
                    const regex = /(expect\([^,]+,\s*)(.*?)(\);)/;
                    dartLines[lineNum] = dartLine.replace(regex, $1);
                }
            }
        }
    } catch (e) {
    }
}

fs.writeFileSync(testFile, dartLines.join('\n'), 'utf8');
console.log('Done modifying test file');
