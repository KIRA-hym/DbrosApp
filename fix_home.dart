import 'dart:io';

void main() {
  final file = File('lib/screens/home_page.dart');
  var content = file.readAsStringSync();
  
  // Find the exact Icon(Icons.map) and add the badge logic next to it inside the Stack if it's there.
  // Actually, I can just find Icons.map and wrap the whole Icon in a Badge if I import badges. Or simply use a Stack.
  
  // Let's replace:
  // Icon(
  //   Icons.map,
  //   color: Theme.of(context).primaryColor,
  //   size: isTablet ? 26 : 22,
  // ),
  // with:
  // Stack(
  //   clipBehavior: Clip.none,
  //   children: [
  //     Icon(Icons.map, color: Theme.of(context).primaryColor, size: isTablet ? 26 : 22),
  //     if (_hasMapUpdate)
  //       Positioned(right: -2, top: -2, child: Container(padding: EdgeInsets.all(3), decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: Text('N', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)))),
  //   ],
  // ),

  content = content.replaceAll(
    '''Icon(
                                Icons.map,
                                color: Theme.of(context).primaryColor,
                                size: isTablet ? 26 : 22,
                              ),''',
    '''Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(Icons.map, color: Theme.of(context).primaryColor, size: isTablet ? 26 : 22),
                                  if (_hasMapUpdate)
                                    Positioned(right: -2, top: -2, child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Text('N', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)))),
                                ],
                              ),'''
  );
  
  content = content.replaceAll(
    '''Icon(Icons.map, color: Color(0xFFFFC700), size: 20)''',
    '''Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(Icons.map, color: Color(0xFFFFC700), size: 20),
                                  if (_hasMapUpdate)
                                    Positioned(right: -2, top: -2, child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Text('N', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)))),
                                ],
                              )'''
  );

  file.writeAsStringSync(content);
}