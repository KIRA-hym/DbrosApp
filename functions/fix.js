const fs = require('fs');

let content = fs.readFileSync('C:\\dbros_app\\functions\\index.js', 'utf8');

content = content.replace(
  "if (data.location && data.location.latitude && data.location.longitude) {",
  "if (data.start_lat && data.start_lng) {"
);
content = content.replace(
  "const type = data.platform || 'other';",
  "const type = data.program || 'other';"
);
content = content.replace(
  "start_lat: data.location.latitude,",
  "start_lat: data.start_lat,"
);
content = content.replace(
  "start_lng: data.location.longitude,",
  "start_lng: data.start_lng,"
);

fs.writeFileSync('C:\\dbros_app\\functions\\index.js', content);
