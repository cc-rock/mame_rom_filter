import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

const String version = '0.0.1';

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show additional command output.',
    )
    ..addOption(
      'romlist',
      abbr: 'r',
      mandatory: true,
      help: 'A text file with all rom names to include, one per line.',
    )
    ..addOption(
      'input',
      abbr: 'i',
      mandatory: true,
      help: 'Input dat file.',
    )
    ..addOption(
      'output',
      abbr: 'o',
      mandatory: true,
      help: 'Output dat file.',
    );
}

void printUsage(ArgParser argParser) {
  print('Usage: dart rom_filter.dart <flags> [arguments]');
  print(argParser.usage);
}

void main(List<String> arguments) async {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);
    bool verbose = false;

    // Process the parsed arguments.
    if (results.wasParsed('help')) {
      printUsage(argParser);
      return;
    }
    if (results.wasParsed('verbose')) {
      verbose = true;
    }

    final romListFileName = results.option('romlist') ?? '';
    final inputFileName = results.option('input') ?? '';
    final outputFileName = results.option('output') ?? '';

    final romNames = File(romListFileName).readAsLinesSync();
    final inputStream = File(inputFileName).openRead();

    if (verbose) {
      print('romList File Name: $romListFileName');
      print('input File Name: $inputFileName');
      print('output File Name: $outputFileName');
      for (final romName in romNames) {
        print('romName: $romName');
      }
    }

    final elementsStream = inputStream
        .transform(Utf8Decoder())
        .toXmlEvents()
        .selectSubtreeEvents(
            (event) => event.name == 'machine' || event.name == 'header')
        .toXmlNodes()
        .flatten()
        .where((node) => node is XmlElement)
        .cast<XmlElement>();

    final romsFound = <XmlElement>[];
    final devices = <String, XmlElement>{};

    XmlElement? header;

    final requiredDevices = <String>{};

    void addRequiredDevicesRecursively(XmlElement element) {
      final deviceNames = element.children
          .where(
            (it) => it is XmlElement && it.name.local == 'device_ref',
          )
          .map((it) => (it as XmlElement).getAttribute('name')!);
      for (final deviceName in deviceNames) {
        requiredDevices.add(deviceName);
        addRequiredDevicesRecursively(devices[deviceName]!);
      }
    }

    await elementsStream.forEach(
      (element) {
        if (element.name.local == 'header') {
          header = element;
          return;
        }
        if (romNames.contains(element.getAttribute('name'))) {
          romsFound.add(element);
        }
        if (element.getAttribute("isdevice") == "yes") {
          devices[element.getAttribute('name')!] = element;
        }
      },
    );

    final outputStream = File(outputFileName).openWrite();

    outputStream.write('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE datafile PUBLIC "-//Logiqx//DTD ROM Management Datafile//EN" "http://www.logiqx.com/Dats/datafile.dtd">

<datafile>
''');
    outputStream.write(header);
    outputStream.write('\n');

    for (final rom in romsFound) {
      addRequiredDevicesRecursively(rom);
      outputStream.write(rom);
      outputStream.write('\n');
    }

    for (final deviceName in requiredDevices) {
      outputStream.write(devices[deviceName]!);
      outputStream.write('\n');
    }

    outputStream.write('</datafile>');

    await outputStream.flush();
    await outputStream.close();

    if (verbose) {
      final notFoundRoms = {...romNames};
      for (final rom in romsFound) {
        notFoundRoms.remove(rom.getAttribute('name'));
      }
      for (final romName in notFoundRoms) {
        print('Not found: $romName');
      }
    }
  } on FormatException catch (e) {
    // Print usage information if an invalid argument was provided.
    print(e.message);
    print('');
    printUsage(argParser);
  } catch (e) {
    print(e);
  }
}
