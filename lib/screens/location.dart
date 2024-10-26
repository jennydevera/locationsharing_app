import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';

class LocationsScreen extends StatefulWidget {
  @override
  _LocationsScreenState createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  List<Map<String, dynamic>> mySharedLocations = [];
  List<Map<String, dynamic>> friendsSharedLocations = [];
  LatLng? _currentUserLatLng;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  void _loadLocations() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      DocumentSnapshot userSnapshot = await FirebaseFirestore.instance
          .collection('accounts')
          .doc(currentUser.uid)
          .get();

      if (!userSnapshot.exists) {
        print('User document not found.');
        return;
      }

      String firstname = userSnapshot['firstname'];
      String lastname = userSnapshot['lastname'];
      String fullName = '$firstname $lastname';

      QuerySnapshot myQuerySnapshot = await FirebaseFirestore.instance
          .collection('locations')
          .where('sharedBy', isEqualTo: fullName)
          .get();

      List<Map<String, dynamic>> myLocations = [];

      for (var doc in myQuerySnapshot.docs) {
        double latitude = double.tryParse(doc['latitude']) ?? 0.0;
        double longitude = double.tryParse(doc['longitude']) ?? 0.0;

        GeoPoint geoPoint = GeoPoint(latitude, longitude);

        List<Placemark> placemarks = await placemarkFromCoordinates(
          geoPoint.latitude,
          geoPoint.longitude,
        );

        String address = placemarks.isNotEmpty
            ? placemarks.first.street ?? 'Unknown address'
            : 'Unknown address';

        myLocations.add({
          'id': doc.id,
          'address': address,
          'timestamp': doc['timestamp'],
          'firstname': doc['firstname'],
          'lastname': doc['lastname'],
          'geoPoint': geoPoint,
        });
      }

      myLocations.sort((a, b) => DateTime.parse(b['timestamp'])
          .compareTo(DateTime.parse(a['timestamp'])));

      QuerySnapshot friendsQuerySnapshot = await FirebaseFirestore.instance
          .collection('locations')
          .where('userID', isEqualTo: currentUser.uid)
          .get();

      List<Map<String, dynamic>> friendsLocations = [];

      for (var doc in friendsQuerySnapshot.docs) {
        double latitude = double.tryParse(doc['latitude']) ?? 0.0;
        double longitude = double.tryParse(doc['longitude']) ?? 0.0;

        GeoPoint geoPoint = GeoPoint(latitude, longitude);

        List<Placemark> placemarks = await placemarkFromCoordinates(
          geoPoint.latitude,
          geoPoint.longitude,
        );

        String address = placemarks.isNotEmpty
            ? placemarks.first.street ?? 'Unknown address'
            : 'Unknown address';

        friendsLocations.add({
          'address': address,
          'timestamp': doc['timestamp'],
          'sharedBy': doc['sharedBy'],
          'geoPoint': geoPoint,
        });
      }

      friendsLocations.sort((a, b) => DateTime.parse(b['timestamp'])
          .compareTo(DateTime.parse(a['timestamp'])));

      Position currentPosition = await Geolocator.getCurrentPosition();
      _currentUserLatLng =
          LatLng(currentPosition.latitude, currentPosition.longitude);

      setState(() {
        mySharedLocations = myLocations;
        friendsSharedLocations = friendsLocations;
      });
    } catch (e) {
      print('Failed to load locations: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load locations')),
      );
    }
  }

  void _stopSharingLocation(String documentId) async {
    try {
      await FirebaseFirestore.instance
          .collection('locations')
          .doc(documentId)
          .delete();

      setState(() {
        mySharedLocations
            .removeWhere((location) => location['id'] == documentId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stopped sharing location.')),
      );
    } catch (e) {
      print('Failed to stop sharing location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to stop sharing location.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                colors: [
                  Colors.pink.shade400.withOpacity(0.8),
                  Colors.blue.shade900.withOpacity(0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )),
            ),
          ),
        ),
        title: Text(
          'Locations Log',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.5),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Your Shared Locations",
                    style: TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8.0),
                  ...mySharedLocations.map((location) => ListTile(
                        title: Text(location['address']),
                        subtitle: Text(
                          'Shared with: ${location['firstname']} ${location['lastname']}\n'
                          'At: ${DateFormat.yMMMd().add_jm().format(DateTime.parse(location['timestamp']))}',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.stop, color: Colors.red),
                          onPressed: () => _stopSharingLocation(location['id']),
                        ),
                      )),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.5),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Friends' Shared Locations",
                    style: TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8.0),
                  ...friendsSharedLocations.map((location) => ListTile(
                        title: Text(location['address']),
                        subtitle: Text(
                          'Shared by: ${location['sharedBy']}\n'
                          'At: ${DateFormat.yMMMd().add_jm().format(DateTime.parse(location['timestamp']))}',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.location_pin, color: Colors.green),
                          onPressed: () {
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (_) => MapViewScreen(
                                  initialPosition: LatLng(
                                    location['geoPoint'].latitude,
                                    location['geoPoint'].longitude,
                                  ),
                                  userLatLng: _currentUserLatLng,
                                  friendName: location['sharedBy'],
                                ),
                              ),
                            );
                          },
                        ),
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MapViewScreen extends StatelessWidget {
  final LatLng initialPosition;
  final LatLng? userLatLng;
  final String friendName;

  const MapViewScreen({
    Key? key,
    required this.initialPosition,
    this.userLatLng,
    required this.friendName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Location on Map'),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: initialPosition,
          zoom: 15.0,
        ),
        markers: {
          Marker(
            markerId: MarkerId("friendLocation"),
            position: initialPosition,
            infoWindow: InfoWindow(title: friendName),
          ),
          if (userLatLng != null)
            Marker(
              markerId: MarkerId("yourLocation"),
              position: userLatLng!,
              infoWindow: InfoWindow(title: 'Your location'),
            ),
        },
      ),
    );
  }
}
