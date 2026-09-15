fetch('https://generativelanguage.googleapis.com/v1beta/models?key=AIzaSyBUj35nhPjFGD0ex95PyD5f5mCgpDCXmrU').then(res => res.json()).then(data => console.log(data.models.map(m => m.name)));
