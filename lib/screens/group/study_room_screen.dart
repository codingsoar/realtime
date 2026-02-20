import 'package:flutter/material.dart';

class StudyRoomScreen extends StatefulWidget {
  final String roomTitle;
  final String roomId;

  const StudyRoomScreen({
    super.key,
    this.roomTitle = '함께 공부해요',
    this.roomId = 'mock_room_1',
  });

  @override
  State<StudyRoomScreen> createState() => _StudyRoomScreenState();
}

class _StudyRoomScreenState extends State<StudyRoomScreen> {
  final List<Map<String, dynamic>> _participants = [
    {'name': 'Me', 'isMe': true, 'status': 'studying', 'avatar': null},
    {'name': 'Learner1', 'isMe': false, 'status': 'studying', 'avatar': null},
    {'name': 'Sleepy', 'isMe': false, 'status': 'resting', 'avatar': null},
    {'name': 'Coder', 'isMe': false, 'status': 'studying', 'avatar': null},
    {'name': 'Offline', 'isMe': false, 'status': 'offline', 'avatar': null},
    {'name': 'Topper', 'isMe': false, 'status': 'studying', 'avatar': null},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.roomTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              '참여자 ${_participants.length}/8',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.chat_bubble_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.85,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _participants.length,
              itemBuilder: (context, index) {
                final user = _participants[index];
                return _buildUserCard(user);
              },
            ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: 20 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('초대하기'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('나가기'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final bool isMe = user['isMe'] as bool;
    final String status = user['status'] as String;
    late Color statusColor;
    late String statusText;
    late IconData statusIcon;

    switch (status) {
      case 'studying':
        statusColor = const Color(0xFF4CAF50);
        statusText = '공부 중';
        statusIcon = Icons.timer;
        break;
      case 'resting':
        statusColor = const Color(0xFFFF9800);
        statusText = '휴식 중';
        statusIcon = Icons.coffee;
        break;
      default:
        statusColor = Colors.grey;
        statusText = '오프라인';
        statusIcon = Icons.person_off;
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(20),
        border: isMe ? Border.all(color: const Color(0xFF6C63FF), width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[800],
                ),
                child: Icon(
                  Icons.person,
                  size: 40,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF2C2C2C), width: 3),
                ),
                child: Icon(statusIcon, size: 12, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            user['name'] as String,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
