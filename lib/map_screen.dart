import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'marker_data.dart';


const String apiKey = 'api_key';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {

  final MapController _mapController = MapController();
  List<MarkerData> _markerData = [];
  List<Marker> _markers = [];
  LatLng? _selectedPosition;
  LatLng? _mylocation;
  LatLng? _draggedPosition;
  bool _isDragging = false;
  bool _isRouting = false;
  List<LatLng> _routePoints = [];
  TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  double _alpha = 1.0;
  double _beta = 1.0;
  double _gamma = 1.0;
  double _delta = 1.0;
  double _epsilon = 1.0;
  int _spot_id = 1;
  List<Map> _parkingSpots = [];
  String _destinationName = '';
  final Random random = Random();

  Future<Position> _determinePosition() async{
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if(!serviceEnabled) {
      return Future.error("Location services are disabled");
    }

    permission = await Geolocator.checkPermission();
    if(permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if(permission == LocationPermission.denied) {
        return Future.error("Location permissions are denied");
      }
    }
    if(permission == LocationPermission.deniedForever) {
      return Future.error("Location permissions are permanently denied");
    }

    return await Geolocator.getCurrentPosition();
  }

  void _showCurrentLocation() async {
    try {
      Position position = await _determinePosition();
      LatLng currentLatLng = LatLng(position.latitude, position.longitude);
      _mapController.move(currentLatLng, 15.0);
      setState(() {
        _mylocation = currentLatLng;
      });
    } catch(e) {
      print(e);
    }
  }

  void _addMarker(LatLng position, String title, String description) {
    setState(() {
      final markerData = MarkerData(position: position, title: title, description: description);
      _markerData.add(markerData);
      _markers.add(
        Marker(
          point: position,
          width: 80,
          height: 80,
          child: GestureDetector(
            onTap: () => _showMarkerInfo(markerData),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if(title != '')
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        title,
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    ),
                  Icon(
                    Icons.location_on,
                    color: Colors.redAccent,
                    size: 40,
                  ),
                ],
              ),
            )
          )
        )
      );
    });
  }

  void _showMarkerInfo(MarkerData markerData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(markerData.title),
        content: Text(markerData.description),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Future<void> _searchPlaces(String query) async {
    if(query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    final url = 'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=5';
    final response = await http.get(Uri.parse(url));
    final data = json.decode(response.body);

    if(data.isNotEmpty) {
      setState(() {
        _searchResults = data;
      });
    } else {
      setState(() {
        _searchResults = [];
      });
    }
  }

  void _moveToLocation(double Lat, double Lon) {
    LatLng location = LatLng(Lat, Lon);
    _mapController.move(location, 15.0);
    setState(() {
      _markers.clear();
      _selectedPosition = location;
      _searchResults = [];
      _isSearching = false;
      _searchController.clear();
    });

    _addMarker(location, "Dest", _destinationName);
    _getParkingSpots(location);
  }

Future<List<LatLng>> _getRoute(LatLng start, LatLng end) async {
  final String url =
      'https://api.openrouteservice.org/v2/directions/driving-car?api_key=$apiKey&start=${start.longitude},${start.latitude}&end=${end.longitude},${end.latitude}';

  final response = await http.get(Uri.parse(url));

  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    final List<dynamic> geometry = data['features'][0]['geometry']['coordinates'];

    // Decode geometry into a list of LatLng
    return geometry
        .map((coord) => LatLng(coord[1], coord[0]))
        .toList();
  } else {
    throw Exception('Failed to fetch route');
  }
}

Future<void> _getParkingSpots(LatLng location) async {
  _parkingSpots = [];

  showDialog(
    context: context,
    barrierDismissible: false, // Prevent dismissal by tapping outside
    builder: (BuildContext context) => AlertDialog(
      backgroundColor: Colors.white.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(), // Loading animation
          SizedBox(height: 15),
          Text("Finding the best parking spots..."),
        ],
      ),
    )
  );

  final double radius = 500; // Search within 1000 meters
  final url =
      'https://api.openrouteservice.org/pois?api_key=$apiKey';

  final body = json.encode({
    "request": "pois",
    "geometry": {
      "geojson": {
        "type": "Point",
        "coordinates": [location.longitude, location.latitude]
      },
      "buffer": radius
    },
    "filters": {
      "category_ids": [601], // ORS category ID for parking areas
    },
    "limit": 10
  });

  try {
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': apiKey,
        'Accept': 'application/json, application/geo+json, application/gpx+xml, img/png; charset=utf-8'
      },
      body: body,
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> features = data['features'];
      if (features.isEmpty) _noResultDialog();
      else {
        for (var feature in features) {
          final coords = feature['geometry']['coordinates'];

          int fee_idx = random.nextInt(((100.0 - 50.0) / 5.0).floor() + 1);
          final parkingSpotLocation = LatLng(coords[1], coords[0]);
          String placeName = '';
          if(feature['properties'].containsKey('osm_tags')) placeName = feature['properties']['osm_tags']['name'];

          // Call function to calculate distances
          final distanceFromUserLocation = await _getDistance(_mylocation!, parkingSpotLocation, 'driving');
          final distanceFromDestination = await _getDistance(location, parkingSpotLocation, 'walking');

          // Simulate parking availability probability (replace with dynamic values later)
          final double parkingAvailability = await _getParkingAvailabilityProbability(_spot_id.toString(), distanceFromUserLocation['duration']);
          _spot_id++;

          _parkingSpots.add({
            'location': parkingSpotLocation,
            'data': {
              'distanceFromUserLocation': distanceFromUserLocation['distance'],
              'distanceFromDestination': distanceFromDestination['distance'],
              'parkingFee': 50.0 + fee_idx * 5.0,
              'trafficDensity': random.nextInt(21),
              'parkingAvailability': parkingAvailability,
              'name': placeName
            }
          });
        }
        // Iterate over features and add markers using your _addMarker function
        _spot_id = 1;
        Navigator.of(context).pop();
        if(_parkingSpots.isNotEmpty) _calculateAndRouteToBestParkingSpot(_parkingSpots);
      }
    } else throw Exception('Failed to fetch parking spots');
  } catch (e) {
    print('Unhandled Exception: $e');
    _noResultDialog();
  }
}

void _noResultDialog() {
  Navigator.of(context).pop();
  showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('There is no parking spots within 500m radius around!'),
    actions: [
        IconButton(
          onPressed: () {
            Navigator.pop(context);
          },
          icon: Icon(Icons.close),
        ),
      ],
    ),
  );
}


Future<void> _calculateAndRouteToBestParkingSpot(List<Map> parkingSpots) async {
  double bestScore = double.infinity; // Start with a very high score for comparison
  Map<String, dynamic> bestData = { '': ''};

  for (var parkingSpot in parkingSpots) {
    final Map<String, dynamic> data = parkingSpot['data'];

    // Calculate the route score
    final routeScore = _calculateRouteScore(
      data['distanceFromUserLocation'],
      data['distanceFromDestination'],
      data['parkingFee'],
      data['trafficDensity'],
      data['parkingAvailability'],
      _alpha,
      _beta,
      _gamma,
      _delta,
      _epsilon
    );

    if (routeScore < bestScore) {
      bestScore = routeScore;
      bestData = {
        'bestScore': routeScore,
        'bestLocation': parkingSpot['location'],
        'bestData': data
      };
    }
    // Call your _addMarker function for each feature
    _addMarker(
      parkingSpot['location'], // Marker location
      '',
      'Name: ${data['name']} \nDriving: ${data['distanceFromUserLocation']} meters\nWalking: ${data['distanceFromDestination']} meters\nParking Fee: ${data['parkingFee']}00 VND\nTraffic Density: ${data['trafficDensity']} cars/500m2\nProbability: ${((data['parkingAvailability']*100).toStringAsFixed(2))}%\nRoute Score: ${routeScore.toStringAsFixed(2)}',
    );
  }
  _addMarker(
      bestData['bestLocation'], // Marker location
      'Best',
      'Name: ${bestData['bestData']['name']} \nDriving: ${bestData['bestData']['distanceFromUserLocation']} meters\nWalking: ${bestData['bestData']['distanceFromDestination']} meters\nParking Fee: ${bestData['bestData']['parkingFee']}00 VND\nTraffic Density: ${bestData['bestData']['trafficDensity']} cars/500m2\nProbability: ${(bestData['bestData']['parkingAvailability']*100).toStringAsFixed(2)}\nRoute Score: ${bestScore.toStringAsFixed(2)}',
    );
  _startRouteToParkingSpot(bestData['bestLocation']);
}



Future<double> _getParkingAvailabilityProbability(String id, double minutes) async {
  // return 1.0; use this when api is not running
  double result = 0.0; // Default fallback value
  double num_predictions = minutes / 300;
  int final_predict = num_predictions.ceil();
  // Use Future.wait and resolve immediately
  final body = json.encode({
    "num_predictions": final_predict
  });
  final response = await http.post(
    Uri.parse("api_url/predict/$id"),
    headers: {"Content-Type": "application/json"},
    body: body
  );

  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    if (data['predictions'] != null && data['predictions'].isNotEmpty) {
      return 1.0 - data['predictions'][0]['occupancy_rate'];
    } else {
      return result;
    }
  } else {
    return result;
  }
}

double _calculateRouteScore(double travelTime, double walkingDistance, double parkingFee, double trafficDensity, double parkingAvailability, double alpha, double beta, double gamma, double delta, double epsilon) {
  // Calculate the score based on the provided formula
  return alpha * travelTime + beta * walkingDistance * 10 + gamma * parkingFee * 100 + delta * trafficDensity * 100 - epsilon * parkingAvailability * 1000 ;
}

Future<dynamic> _getDistance(LatLng start, LatLng destination, String vehicle) async {
  final String url = "https://api.openrouteservice.org/v2/directions/${vehicle == 'walking' ? 'foot-walking' : 'driving-car'}";
  final body = json.encode({
    "coordinates": [
      [start.longitude, start.latitude],
      [destination.longitude, destination.latitude]
    ]
  });

  final response = await http.post(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': apiKey,
      'Accept': 'application/json, application/geo+json, application/gpx+xml, img/png; charset=utf-8'
    },
    body: body,
  );

  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    final route = data['routes'][0];  // Assume the first route is the one we want

    return { 'distance': route['segments'][0]['distance'], 'duration': route['segments'][0]['duration'] };  // Distance in meters
  } else {
    throw Exception('Failed to fetch travel time and distance');
  }
}

void _startRouteToParkingSpot(LatLng parkingSpotLocation) async {
  if (_mylocation == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Please enable your location to get the route')),
    );
    return;
  }

  try {
    // Fetch the route from the current location to the selected parking spot
    final route = await _getRoute(_mylocation!, parkingSpotLocation);
    setState(() {
      _routePoints = route;
    });

    // Optionally, move the map view to show the route
    _mapController.move(parkingSpotLocation, 15.0);
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error fetching route: $e')),
    );
  }
}

void _calculateRoute() async {
    if (_mylocation == null || _selectedPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a destination')),
      );
      return;
    }

    setState(() {
      _isRouting = true;
    });

    try {
      final route = await _getRoute(_mylocation!, _selectedPosition!);
      setState(() {
        _routePoints = route;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching route: $e')),
      );
    } finally {
      setState(() {
        _isRouting = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _searchPlaces(_searchController.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
       appBar: AppBar(
      title: const Text("aLot"),
    ),
    drawer: Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Add a User Profile Header
          const UserAccountsDrawerHeader(
            accountName: Text("Thuy Lê"),
            accountEmail: Text("+84903758706"),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(
                Icons.person,
                size: 50,
                color: Colors.blue,
              ),
            ),
          ),
          // Add Sidebar Menu Items
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text("Lịch sử đặt chỗ"),
            onTap: () {
              // Add logic for booking history
              Navigator.pop(context); // Close the drawer
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite),
            title: const Text("Yêu thích"),
            onTap: () {
              // Add logic for favorites
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text("Cài đặt"),
            onTap: () {
              // Add logic for settings
              Navigator.pop(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text("Đăng xuất"),
            onTap: () {
              // Add logic for logout
              Navigator.pop(context);
            },
          ),
        ],
      ),
    ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialZoom: 13.0,
              onTap: (tapPosition, LatLng) {
                setState(() {
                  _selectedPosition = LatLng;
                  _markers = [];
                  _addMarker(LatLng, '', '');
                  _draggedPosition = _selectedPosition;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
              ),
              MarkerLayer(markers: _markers),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.blue,
                      strokeWidth: 4.0,
                    ),
                  ],
                ),
              Positioned(
                bottom: 20,
                left: 20,
                child: FloatingActionButton(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  onPressed: () {
                    // Show modal when the button is pressed
                    showModalBottomSheet(
                      context: context,
                      builder: (context) {
                        return StatefulBuilder(
                          builder: (context, setModalState) {
                            return Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Adjust Priority',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  Row(
                                    children: [
                                      Text('Distance from my location:'),
                                      Expanded(
                                        child: Slider(
                                          value: _alpha,
                                          min: 0,
                                          max: 10,
                                          divisions: 20,
                                          label: _alpha.toStringAsFixed(1),
                                          onChanged: (double value) {
                                            setModalState(() {
                                              _alpha = value;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Text('Distance from destination:'),
                                      Expanded(
                                        child: Slider(
                                          value: _beta,
                                          min: 0,
                                          max: 10,
                                          divisions: 20,
                                          label: _beta.toStringAsFixed(1),
                                          onChanged: (double value) {
                                            setModalState(() {
                                              _beta = value;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Text('Parking fee:'),
                                      Expanded(
                                        child: Slider(
                                          value: _gamma,
                                          min: 0,
                                          max: 10,
                                          divisions: 20,
                                          label: _gamma.toStringAsFixed(1),
                                          onChanged: (double value) {
                                            setModalState(() {
                                              _gamma = value;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Text('Traffic density:'),
                                      Expanded(
                                        child: Slider(
                                          value: _delta,
                                          min: 0,
                                          max: 10,
                                          divisions: 20,
                                          label: _delta.toStringAsFixed(1),
                                          onChanged: (double value) {
                                            setModalState(() {
                                              _delta = value;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Text('Parking availability:'),
                                      Expanded(
                                        child: Slider(
                                          value: _epsilon,
                                          min: 0,
                                          max: 10,
                                          divisions: 20,
                                          label: _epsilon.toStringAsFixed(1),
                                          onChanged: (double value) {
                                            setModalState(() {
                                              _epsilon = value;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      // When the button is pressed, recalculate the best parking spot
                                      _markers.clear();
                                      _routePoints.clear();
                                      _addMarker(_selectedPosition!, 'Dest', _destinationName);
                                      if (_selectedPosition != null) {
                                        // Recalculate best parking spots using the selected position
                                        _calculateAndRouteToBestParkingSpot(_parkingSpots);
                                      } else {
                                        // If no position is selected, show a message or handle it accordingly
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Please select a location first!')),
                                        );
                                      }

                                      // Close the modal
                                      Navigator.of(context).pop();
                                    },
                                    child: Text('Apply and recalculate'),
                                  ),
                                ],
                              ),
                            );
                          }
                        );
                      },
                    );
                  },
                  child: Icon(Icons.settings),
                ),
              ),
              if(_isDragging && _draggedPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _draggedPosition!,
                      width: 80,
                      height: 80,
                      child: Icon(
                        Icons.location_on,
                        color: Colors.indigo,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              if(_mylocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _mylocation!,
                      width: 80,
                      height: 80,
                      child: Icon(
                        Icons.location_on,
                        color: Colors.green,
                        size: 40,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            bottom: 90,
            right: 20,
            child: FloatingActionButton(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              onPressed: _calculateRoute,
              child: Icon(Icons.directions),
            ),
          ),
          Positioned(
            bottom: 90,
            left: 20,
            child: FloatingActionButton(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              onPressed: () {
                setState(() {
                  _markers.clear();         // Clear all markers
                  _markerData.clear();      // Clear marker data
                  _routePoints.clear();     // Clear the route line
                  _selectedPosition = null; // Reset selected position
                  _draggedPosition = null;  // Reset dragged position
                  _isDragging = false;
                  _destinationName = '';      // Stop dragging mode
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Map cleared!')),
                );
              },
              child: Icon(Icons.clear),
            ),
          ),
          // Search bar
          Positioned(
            top: 40,
            left: 15,
            right: 15,
            child: Column(
              children: [
                SizedBox(
                  height: 55,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search places...',
                      filled: true,
                      fillColor: Colors.white70,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(50),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: Icon(Icons.search),
                      suffixIcon: _isSearching ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _isSearching = false;
                            _searchResults = [];
                          });
                        },
                        icon: Icon(Icons.clear),
                      ): null,
                    ),
                    onTap: () {
                      setState(() {
                        _isSearching = true;
                      });
                    },
                  ),
                ),
                if(_isSearching && _searchResults.isNotEmpty)
                  Container(
                    color: Colors.white,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (ctx, index) {
                        final place = _searchResults[index];

                        return ListTile(
                          title: Text(
                            place['display_name'],
                          ),
                          onTap: () {
                            final lat = double.parse(place['lat']);
                            final lon = double.parse(place['lon']);
                            _destinationName = place['display_name'];
                            _moveToLocation(lat, lon);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.indigo,
                  onPressed: _showCurrentLocation,
                  child: Icon(Icons.location_searching_rounded),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
