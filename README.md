WordPress for iOS

[![Build Status](https://travis-ci.org/wordpress-mobile/WordPress-iOS.png)](https://travis-ci.org/wordpress-mobile/WordPress-iOS)

## Resources

### Developer blog & Handbook

Blog: http://make.wordpress.org/mobile

Handbook: http://make.wordpress.org/mobile/handbook/

### Style guide

https://github.com/wordpress-mobile/WordPress-iOS/wiki/WordPress-for-iOS-Style-Guide

### How to Contribute

http://make.wordpress.org/mobile/handbook/pathways/ios/how-to-contribute/

## Folder Structure

**Derived Sources** - This is where the project outputs the generated `WordPressComApiCredentials.m` file. As a part of the build process the project looks for a file located at `~/.wpcom_app_credentials` and uses the values there to generate `WordPressComApiCredentials.m`.

**WordPressApi** - There are a few files here related to the WordPress API. The primary class is `WordPressApi` which is used to access the varied data that the app needs to function. There is a `gencredentials.rb` file here which is what is used by the build process to generate `WordPressComApiCredentials.m`. Note that the `WordPressComiApCredentials.m` file in this folder will get overridden by the output from `gencredentials.rb`.

**Classes** - The bulk of the app's code lives within this folder in various subdirectories(described below).

**Classes/Categories** - This is where we store all of the app's categories.

**Classes/Models** - This is where all of the app's models live. Some of the models here are Core Data objects, some are just Plain Old Objective-C Object's. 

**Classes/Networking** - We've been moving most of the network code in the app into this folder. There are various classes in this folder which contain most if not all the networking code related to a particular entity within the app(i.e. Account Notifications, Reader).

**Classes/Services** - This folder contains the classes housing the business logic for various entities within the app. The app's views generally interact with these classes and not directly with the classes within the `Classes/Networking` folder.

**Classes/System** - This folder contains two system classes: the app delegate and a constants file.

**Classes/Utility** - We generally put utility classes that are either more cross cutting or don't logically fit anywhere else in this folder. Within this folder is the `Analytics` folder which houses our analytics package for the app.

**Classes/ViewRelated** - Within this folder are a series sub folders for the various parts of the app and within each folder are all the code related view files. There's a general `Cells` and `Views` folder here which contain classes that span more than one section of the app.

**Vendor** - There are a few 3rd party libraries here which when initially added to the app didn't have CocoaPods.

**Other Sources** - There are a few files here dealing with localization of strings as well as the prefix for the project and `main.m`.

**WordPressTest** - Where we put the unit tests and integration tests for the project.

## Building

Starting with changeset 3633 version 3.2, WordPress for iOS uses Cocoapods (http://cocoapods.org/) to manage third party libraries.  Trying to build the project by itself (WordPress.xcproj) after launching will result in an error, as the resources managed by cocoapods are not included.  Instead, launch the workspace by either double clicking on WordPress.xcworkspace file, or launch Xcode and choose File > Open and browse to WordPress.xcworkspace. 

You will not be able to connect to WordPress.com hosted blogs when compiling WordPress for iOS yourself.  See the following handbook page for more information: http://make.wordpress.org/mobile/handbook/general-guides/connecting-to-wordpress-com/
