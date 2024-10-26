import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:locationapp/screens/friends.dart';
import 'package:locationapp/screens/loginpage.dart';
import 'package:locationapp/screens/location.dart';

class HomepageScreen extends StatefulWidget {
  final String userEmail;

  const HomepageScreen({Key? key, required this.userEmail}) : super(key: key);

  @override
  State<HomepageScreen> createState() => _HomepageScreenState();
}

class _HomepageScreenState extends State<HomepageScreen> {
  static final initialPosition = LatLng(16.065853, 120.596976);
  LatLng? selectedPosition;
  String? selectedLocationName;
  String? sharedFriendID;
  Set<String> sharedFriendIDs = Set<String>();
  late GoogleMapController mapController;
  Position? _currentLocation;
  Set<Marker> markers = {
    Marker(
      markerId: MarkerId("1"),
      position: initialPosition,
    ),
  };
  bool isShareContainerVisible = false;
  List<Map<String, String>> friendsList = [];
  List<LatLng> polylineCoordinates = [];
  Set<Polyline> polylines = {};

  //email for current user that will appear on top
  get userEmail => null;

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    }

    return await Geolocator.getCurrentPosition();
  }

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    loadFriendsFirestore();
    _trackLocation();
  }

  void _trackLocation() {
    Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      if (_currentLocation == null ||
          (position.latitude != _currentLocation!.latitude &&
              position.longitude != _currentLocation!.longitude)) {
        setState(() {
          _currentLocation = position;
          polylineCoordinates
              .add(LatLng(position.latitude, position.longitude));
          markers = Set.from([
            Marker(
              markerId: MarkerId("currentLocation"),
              position: LatLng(position.latitude, position.longitude),
              infoWindow: InfoWindow(title: "You are here"),
            ),
          ]);
          polylines = Set.from([
            Polyline(
              polylineId: PolylineId("route"),
              color: Colors.blue,
              points: List.from(polylineCoordinates),
              width: 5,
            ),
          ]);
          mapController.animateCamera(
            CameraUpdate.newLatLng(
              LatLng(position.latitude, position.longitude),
            ),
          );
        });
      }
    });
  }

  void _getCurrentLocation() async {
    try {
      Position position = await _determinePosition();
      setState(() {
        _currentLocation = position;
      });
    } catch (e) {
      print("Error getting current location: $e");
    }
  }

  void loadFriendsFirestore() async {
    try {
      print('Loading friends for user: ${widget.userEmail}');
      DocumentSnapshot documentSnapshot = await FirebaseFirestore.instance
          .collection('accounts')
          .doc(widget.userEmail)
          .get();
      print('User document: ${documentSnapshot.data()}');

      if (documentSnapshot.exists) {
        List<String> friendsIds =
            List<String>.from(documentSnapshot.get('friends') ?? []);
        print('Friends IDs: $friendsIds');

        List<Map<String, String>> tempFriends = [];

        for (String friendID in friendsIds) {
          print('Loading friend: $friendID');
          DocumentSnapshot friendSnapshot = await FirebaseFirestore.instance
              .collection('accounts')
              .doc(friendID)
              .get();

          if (friendSnapshot.exists) {
            String firstname = friendSnapshot.get('firstname') ?? '';
            String lastname = friendSnapshot.get('lastname') ?? '';
            print('Friend details: $firstname $lastname');

            tempFriends.add({
              'name': '$firstname $lastname',
              'userID': friendID,
            });
          } else {
            print('Friend document not found for userID: $friendID');
          }
        }

        setState(() {
          friendsList = tempFriends;
          print('Friends list updated: $friendsList');
        });
      } else {
        print('User document not found for email: ${widget.userEmail}');
      }
    } catch (e) {
      print('Failed to load friend list: $e');
    }
  }

  void updateFriendsList() {
    loadFriendsFirestore();
  }

  void _shareLocationWithFriend(String userID) async {
    if (_currentLocation == null) {
      print('Current location is not available.');
      return;
    }

    LatLng currentLatLng =
        LatLng(_currentLocation!.latitude, _currentLocation!.longitude);

    List<Placemark> placemarks = await placemarkFromCoordinates(
        currentLatLng.latitude, currentLatLng.longitude);
    String address =
        placemarks.isNotEmpty ? placemarks.first.name ?? '' : 'Unknown address';

    try {
      DocumentSnapshot friendSnapshot = await FirebaseFirestore.instance
          .collection('accounts')
          .doc(userID)
          .get();

      if (!friendSnapshot.exists) {
        print('Friend details not found for userID: $userID');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Friend details not found.')),
        );
        return;
      }

      String? firstname = friendSnapshot.get('firstname') as String?;
      String? lastname = friendSnapshot.get('lastname') as String?;

      if (firstname == null || lastname == null) {
        print(
            'Friend document does not contain required fields: firstname or lastname');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Friend details are incomplete.')),
        );
        return;
      }

      String sharedByID = FirebaseAuth.instance.currentUser!.uid;
      DocumentSnapshot currentUserSnapshot = await FirebaseFirestore.instance
          .collection('accounts')
          .doc(sharedByID)
          .get();
      String? sharedByName = currentUserSnapshot.get('firstname') as String?;

      if (sharedByName == null) {
        sharedByName = 'Unknown';
      }

      CollectionReference sharedLocations =
          FirebaseFirestore.instance.collection('locations');

      sharedLocations.add({
        'address': address,
        'isSharing': true,
        'latitude': currentLatLng.latitude.toString(),
        'longitude': currentLatLng.longitude.toString(),
        'timestamp': DateTime.now().toIso8601String(),
        'userID': userID,
        'firstname': firstname,
        'lastname': lastname,
        'sharedBy': sharedByName,
      }).then((value) {
        setState(() {
          sharedFriendIDs.add(userID);
        });
        print('Location shared with $firstname $lastname');
        print('Attempting to retrieve friend details for userID: $userID');
        print('Friend document retrieved: ${friendSnapshot.data()}');

        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Location shared')));
      }).catchError((error) {
        print('Failed to share location: $error');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to share location')));
      });
    } catch (e) {
      print('Error retrieving friend details: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to retrieve friend details.')),
      );
    }
  }

  void _toggleShareContainer() {
    setState(() {
      isShareContainerVisible = !isShareContainerVisible;
    });
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginPageScreen()),
    );
  }

  Future<Map<String, String>?> _getUserProfile() async {
    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('accounts')
          .where('email', isEqualTo: userEmail)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        DocumentSnapshot documentSnapshot = querySnapshot.docs.first;
        Map<String, dynamic> data =
            documentSnapshot.data() as Map<String, dynamic>;
        return {
          'firstname': data['firstname'] ?? '',
          'lastname': data['lastname'] ?? '',
        };
      } else {
        return null;
      }
    } catch (e) {
      print('Error fetching user profile: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                colors: [
                  Colors.pink.shade400.withOpacity(0.5),
                  Colors.blue.shade900.withOpacity(0.5),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )),
            ),
          ),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color.fromARGB(255, 126, 15, 181),
              child: Icon(
                Icons.person,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 8.0),
            Text(
              widget.userEmail,
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => FriendsScreen(
                      currentUserEmail: widget.userEmail,
                      updateFriendsList: updateFriendsList,
                    ),
                  ));
            },
            icon: Icon(
              Icons.people_sharp,
              color: Color.fromARGB(255, 255, 255, 255),
              size: 25,
            ),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                CupertinoPageRoute(builder: (_) => LocationsScreen()),
              );
            },
            icon: Icon(
              Icons.person_pin_circle_sharp,
              color: Colors.white,
              size: 29,
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.logout,
              color: Colors.white,
            ),
            onPressed: _logout,
          ),
        ],
        backgroundColor: Color.fromARGB(255, 226, 64, 124),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            GoogleMap(
              myLocationButtonEnabled: true,
              myLocationEnabled: true,
              initialCameraPosition:
                  CameraPosition(target: initialPosition, zoom: 15),
              markers: markers,
              polylines: polylines,
              onMapCreated: (controller) {
                mapController = controller;
              },
            ),
          ],
        ),
      ),
    );
  }
}
