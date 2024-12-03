import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'marker_data.dart';


const String apiKey = 'api-key';

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
  
  void _showMarkerDialog(BuildContext context, LatLng position) {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Marker'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: descController,
              decoration: InputDecoration(labelText: 'Description'),
            ),
          ]
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _addMarker(position, titleController.text, descController.text);
              Navigator.pop(context);
            },
            child: Text('Add'),
          ),
        ],
      ),
    );
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

    _addMarker(location, "Destination", "Search Result");
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
  });

  print('Request Body: $body');
  print('Request URL: $url');


  final response = await http.post(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json; charset=utf-8', 
      'Authorization': apiKey,
      'Accept': 'application/json, application/geo+json, application/gpx+xml, img/png; charset=utf-8'
    },
    body: body,
  );

  print('Response Code: ${response.statusCode}');
  print('Response Body: ${response.body}');

  if (response.statusCode == 200) {
    final data = json.decode(response.body);  
    final List<dynamic> features = data['features'];

    double bestScore = double.infinity; // Start with a very high score for comparison
    LatLng bestSpotLocation = location;
    Map<String, dynamic> bestData = {
      'time': '0',  // Convert to minutes
      'distance': 0,
    };;

    // Iterate over features and add markers using your _addMarker function
    for (var feature in features) {
      final coords = feature['geometry']['coordinates'];
      final properties = feature['properties'];
      final categoryName = properties['category_ids']['601']['category_name'];
      final parkingSpotLocation = LatLng(coords[1], coords[0]);

      // Call function to calculate distances
      final distanceFromUserLocation = await _getDistance(_mylocation!, parkingSpotLocation);
      final distanceFromDestination = await _getDistance(location, parkingSpotLocation);

      // Simulate parking availability probability (replace with dynamic values later)
      final parkingAvailability = _getParkingAvailabilityProbability();

      // Calculate the route score
      final routeScore = _calculateRouteScore(
        distanceFromUserLocation,
        distanceFromDestination,
        parkingAvailability,
        _alpha,
        _beta,
        _gamma
      );

      // Check if this is the best parking spot (lowest score)
      if (routeScore < bestScore) {
        bestScore = routeScore;
        bestSpotLocation = parkingSpotLocation;
        bestData = { 'distanceFromUserLocation': distanceFromUserLocation, 'distanceFromDestination': distanceFromDestination};
      }

      // Call your _addMarker function for each feature
      _addMarker(
        parkingSpotLocation, // Marker location
        '',
        'Travel time: ${distanceFromUserLocation} meters\nDistance: ${distanceFromDestination} meters\nRoute Score: ${routeScore.toStringAsFixed(2)}',
      );
    }

    _addMarker(
      bestSpotLocation, // Marker location
      'Best',
      'Travel time: ${bestData['distanceFromUserLocation']} mins\nDistance: ${bestData['distanceFromDestination']} meters\nRoute Score: ${bestScore}',
    );
    _startRouteToParkingSpot(bestSpotLocation);
  } else {
    throw Exception('Failed to fetch parking spots');
  }
}

double _getParkingAvailabilityProbability() {
  // Simulate parking availability, this value should be dynamically calculated or retrieved from a real-time system
  return 0.75;  // Example value (75% availability)
}

double _calculateRouteScore(double travelTime, double walkingDistance, double parkingAvailability, double alpha, double beta, double gamma) {
  // Calculate the score based on the provided formula
  return alpha * travelTime + beta * walkingDistance - gamma * parkingAvailability;
}

Future<dynamic> _getDistance(LatLng start, LatLng destination) async {
  final String url = 'https://api.openrouteservice.org/v2/directions/foot-walking';
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
    print('Response Code: ${response.statusCode}');
    print('Response Body: ${response.body}');

    final data = json.decode(response.body);
    final route = data['routes'][0];  // Assume the first route is the one we want
    
    return route['segments'][0]['distance'];  // Distance in meters
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
                                      Text('Parking availability:'),
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
                                  ElevatedButton(
                                    onPressed: () {
                                      // When the button is pressed, recalculate the best parking spot
                                      _markers.clear();
                                      _routePoints.clear();
                                      _addMarker(_selectedPosition!, 'Destination', "Search Result");
                                      if (_selectedPosition != null) {
                                        // Recalculate best parking spots using the selected position
                                        _getParkingSpots(_selectedPosition!);
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
                  _isDragging = false;      // Stop dragging mode
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
                            _moveToLocation(lat, lon);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          // location button
          // _isDragging == false ? Positioned(
          //   bottom: 20,
          //   left: 20,
          //   child: FloatingActionButton(
          //     backgroundColor: Colors.indigo,
          //     foregroundColor: Colors.white,
          //     onPressed: () {
          //       setState(() {
          //         _isDragging = true;
          //       });
          //     },
          //     child: Icon(Icons.add_location),
          //   ),
          // ) : Positioned(
          //   bottom: 20,
          //   left: 20,
          //   child: FloatingActionButton(
          //     backgroundColor: Colors.redAccent,
          //     foregroundColor: Colors.white,
          //     onPressed: () {
          //       setState(() {
          //         _isDragging = false;
          //       });
          //     },
          //     child: Icon(Icons.wrong_location),
          //   ),
          // ),
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
                // if(!_isDragging)
                //   Padding(
                //     padding: EdgeInsets.only(top: 20),
                //     child: FloatingActionButton(
                //       backgroundColor: Colors.green,
                //       foregroundColor: Colors.white,
                //       onPressed: () {
                //         if(_draggedPosition != null) {
                //           _showMarkerDialog(context, _draggedPosition!);
                //         }
                //         setState(() {
                //           _isDragging = false;
                //           _draggedPosition = null;
                //         });
                //       },
                //       child: Icon(Icons.check),
                //     ),
                //   ),
              ],
            ),
          )
        ],
      ),
    );
  }
}