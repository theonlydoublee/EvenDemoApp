import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:demo_ai_even/controllers/pin_text_controller.dart';
import 'package:demo_ai_even/models/pin_text_model.dart';
import 'package:demo_ai_even/services/pin_text_service.dart';
import 'package:demo_ai_even/ble_manager.dart';

class PinTextPage extends StatelessWidget {
  const PinTextPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PinTextController>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pin Text'),
      ),
      body: Obx(() {
        if (controller.notes.isEmpty) {
          return const Center(
            child: Text('No Pin Text yet. Tap + to add one.'),
          );
        }
        
        // Sort notes: pinned first, then by creation date
        final sortedNotes = List<PinText>.from(controller.notes);
        sortedNotes.sort((a, b) {
          if (a.isPinned && !b.isPinned) return -1;
          if (!a.isPinned && b.isPinned) return 1;
          return b.createdAt.compareTo(a.createdAt);
        });
        
        return ListView.builder(
          itemCount: sortedNotes.length,
          itemBuilder: (context, index) {
            final note = sortedNotes[index];
            final originalIndex = controller.notes.indexOf(note);
            final isCurrent = controller.currentNoteIndex.value == originalIndex;
            
            return Card(
              color: note.isPinned 
                  ? Colors.amber.withOpacity(0.1) 
                  : (isCurrent ? Colors.blue.withOpacity(0.1) : null),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: note.isPinned 
                    ? const Icon(Icons.push_pin, color: Colors.amber)
                    : null,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        note.content.length > 50 
                            ? '${note.content.substring(0, 50)}...' 
                            : note.content,
                      ),
                    ),
                    if (note.isPinned)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Text(
                          'Pinned',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: Text('Created: ${note.createdAt.toString().substring(0, 16)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pin/Unpin button
                    IconButton(
                      icon: Icon(
                        note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                        color: note.isPinned ? Colors.amber : null,
                      ),
                      onPressed: () {
                        if (note.isPinned) {
                          controller.unpinNote(originalIndex);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Pin Text unpinned')),
                          );
                        } else {
                          controller.pinNote(originalIndex);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Pin Text pinned')),
                          );
                        }
                      },
                      tooltip: note.isPinned ? 'Unpin' : 'Pin',
                    ),
                    // Send as Text button
                    if (BleManager.get().isConnected)
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () {
                          PinTextService.instance.sendPinText(note.content);
                          controller.currentNoteIndex.value = originalIndex;
                          controller.isDashboardMode.value = true;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Pin Text sent as text to glasses')),
                          );
                        },
                        tooltip: 'Send as Text',
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => controller.removeNote(originalIndex),
                      tooltip: 'Delete',
                    ),
                  ],
                ),
                onTap: () {
                  // Edit note
                  _showEditDialog(context, controller, originalIndex, note.content);
                },
              ),
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, controller),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context, PinTextController controller) {
    final textController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Pin Text'),
        content: TextField(
          controller: textController,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Enter Pin Text content...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (textController.text.trim().isNotEmpty) {
                controller.addNote(textController.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
    BuildContext context, 
    PinTextController controller, 
    int index, 
    String currentContent,
  ) {
    final textController = TextEditingController(text: currentContent);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Pin Text'),
        content: TextField(
          controller: textController,
          maxLines: 5,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (textController.text.trim().isNotEmpty) {
                controller.updateNote(index, textController.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

