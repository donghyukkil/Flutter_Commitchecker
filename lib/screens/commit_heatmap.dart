import 'package:flutter/material.dart';

import 'package:table_calendar/table_calendar.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

import 'package:commitchecker/models/commit_info.dart';
import 'package:commitchecker/components/commit_list.dart';
import 'package:commitchecker/components/repository_dropdown_button.dart';

import 'package:commitchecker/services/github_api.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class CommitHeatmap extends StatefulWidget {
  final String username;
  const CommitHeatmap({Key? key, required this.username}) : super(key: key);

  @override
  _CommitHeatmapState createState() => _CommitHeatmapState();
}

class _CommitHeatmapState extends State<CommitHeatmap> {
  Map<DateTime, List<CommitInfo>> commitData = {};
  DateTime focusedDay = DateTime.now();
  DateTime? selectedDay;
  List<CommitInfo>? selectedCommits;
  bool isLoading = false;
  List<String> repositories = [];
  String? selectedRepository;

  @override
  void initState() {
    super.initState();

    fetchRepositories(widget.username);
  }

  Future<void> fetchRepositories(String username) async {
    try {
      setState(() => isLoading = true);

      List<String> repoNames = await fetchRepositoriesFromAPI(username);

      setState(() {
        isLoading = false;
        repositories = repoNames;
        selectedRepository =
            repositories.isNotEmpty ? repositories.first : null;

        fetchCommitsForMonth(focusedDay);
      });
    } catch (e) {
      setState(() => isLoading = false);

      showErrorDialog('Failed to load repositories: $e');
    }
  }

  void fetchCommitsForMonth(DateTime targetDate) async {
    setState(() => isLoading = true);

    String? repository = selectedRepository;

    if (repository == null) {
      setState(() => isLoading = false);

      return;
    }

    DateTime startOfMonth = DateTime(targetDate.year, targetDate.month, 1);
    DateTime endOfMonth = DateTime(targetDate.year, targetDate.month + 1, 0);
    String since = startOfMonth.toIso8601String();
    String until = endOfMonth.toIso8601String();

    await dotenv.load();
    String? token = dotenv.get('GITHUB_TOKEN');

    final String url =
        'https://api.github.com/repos/${widget.username}/$repository/commits?since=$since&until=$until&per_page=100';

    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': 'token $token',
      });

      if (response.statusCode == 200) {
        List<dynamic> commits = json.decode(response.body);
        Map<DateTime, List<CommitInfo>> newCommitData = {};

        for (var commit in commits) {
          DateTime date =
              DateTime.parse(commit['commit']['author']['date']).toUtc();
          DateTime dateKey = DateTime.utc(date.year, date.month, date.day);

          String commitMessage = commit['commit']['message'];
          String htmlUrl = commit['html_url'];

          newCommitData[dateKey] = (newCommitData[dateKey] ?? [])
            ..add(CommitInfo(
                message: commitMessage, htmlUrl: htmlUrl, date: date));
        }

        setState(() {
          commitData = newCommitData;
          isLoading = false;
        });
      } else {
        throw Exception(
            'Failed to load commits with status code: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => isLoading = false);

      showErrorDialog('Error fetching commits: $e');
    }
  }

  void showErrorDialog(String message) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Error'),
              content: Text(message),
              actions: <Widget>[
                TextButton(
                  child: const Text('OK'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ));
  }

  String formatDate(DateTime? date) {
    if (date == null) {
      return 'No Date Selected';
    }

    return DateFormat('yyyy-MM-dd EEEE').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Commit Heatmap',
          style: TextStyle(
            fontSize: 23,
          ),
        ),
        backgroundColor: Colors.green,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => showCommitStatsForPeriod(
                context, widget.username, selectedRepository),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      focusedDay = DateTime.now();
                    });

                    fetchCommitsForMonth(focusedDay);
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30.0),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 15.0),
                  ),
                  child: const Text(
                    'Today',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(width: 50),
                Expanded(
                  child: RepositoryDropdownButton(
                    selectedRepository: selectedRepository,
                    repositories: repositories,
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedRepository = newValue;
                      });

                      fetchCommitsForMonth(focusedDay);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              flex: 3,
              child: TableCalendar(
                focusedDay: focusedDay,
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2025, 12, 31),
                eventLoader: (day) => commitData[day] ?? [],
                onPageChanged: (focusedDay) {
                  this.focusedDay = focusedDay;

                  fetchCommitsForMonth(focusedDay);
                },
                availableCalendarFormats: const {
                  CalendarFormat.month: 'Month',
                },
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, date, events) {
                    if (events.isNotEmpty) {
                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: events.length > 5
                                ? Colors.red
                                : (events.length > 2
                                    ? Colors.orange
                                    : Colors.green),
                          ),
                          width: 8.0,
                          height: 8.0,
                        ),
                      );
                    }

                    return null;
                  },
                ),
                headerStyle: const HeaderStyle(
                  titleCentered: true,
                ),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    this.selectedDay = selectedDay;
                    selectedCommits = commitData[selectedDay] ?? [];
                  });
                },
              ),
            ),
            if (selectedCommits != null && selectedDay != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatDate(selectedDay),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            Expanded(
              flex: 2,
              child: Scrollbar(
                thumbVisibility: true,
                thickness: 4.0,
                radius: const Radius.circular(5.0),
                child: CommitList(
                  commits: selectedCommits ?? [],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showCommitStatsForPeriod(
      BuildContext context, String username, String? selectedRepository) async {
    if (selectedRepository == null) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: const Text('No repository selected.'),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }

      return;
    }

    final DateTimeRange? pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (pickedRange != null && mounted) {
      try {
        List<CommitInfo> allCommits = await fetchAllCommits(
          username,
          selectedRepository,
        );

        List<CommitInfo> commitsInRange = allCommits.where((commit) {
          return commit.date.isAfter(pickedRange.start) &&
              commit.date.isBefore(pickedRange.end);
        }).toList();

        int commitCount = commitsInRange.length;

        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Commit Statistics'),
              content: Text(
                'You have made $commitCount commits from ${DateFormat('yyyy-MM-dd').format(pickedRange.start)} to ${DateFormat('yyyy-MM-dd').format(pickedRange.end)}.',
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('OK'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Error'),
              content: const Text('Failed to load commits.'),
              actions: <Widget>[
                TextButton(
                  child: const Text('OK'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        }
      }
    }
  }
}
