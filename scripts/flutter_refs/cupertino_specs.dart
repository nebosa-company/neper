import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'harness.dart';

bool en(String st) => st != 'disabled';
VoidCallback? cb(String st) => en(st) ? () {} : null;
const cs = ['rest', 'focus', 'pressed', 'disabled'];
const css = ['rest', 'focus', 'pressed', 'disabled', 'selected'];

BuildContext _ctx(WidgetTester t) => t.element(find.byType(CupertinoPageScaffold).first);
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 800));
}

Widget _section(String st) => CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: Center(
        child: CupertinoListSection.insetGrouped(
          header: const Text('SECTION'),
          children: [
            for (final n in ['One', 'Two', 'Three'])
              CupertinoListTile(key: n == 'Two' ? tk : null, title: Text(n), subtitle: n == 'Two' ? const Text('Detail') : null, leading: const Icon(CupertinoIcons.star_fill), additionalInfo: const Text('Info'), trailing: const CupertinoListTileChevron(), onTap: () {}),
          ],
        ),
      ),
    );

final cupertinoSpecs = <Spec>[
  for (final v in ['plain', 'filled', 'tinted', 'gray'])
    Spec('button-$v', 'button', 'CupertinoButton', cs, (st) {
      const l = Text('Button');
      return switch (v) {
        'plain' => CupertinoButton(key: tk, onPressed: cb(st), child: l),
        'filled' => CupertinoButton.filled(key: tk, onPressed: cb(st), child: l),
        'tinted' => CupertinoButton.tinted(key: tk, onPressed: cb(st), child: l),
        _ => CupertinoButton(key: tk, onPressed: cb(st), color: CupertinoColors.systemGrey5, child: l),
      };
    }),
  Spec('switch', 'switch', 'CupertinoSwitch', css, (st) => CupertinoSwitch(key: tk, value: st == 'selected', onChanged: en(st) ? (_) {} : null)),
  Spec('slider', 'slider', 'CupertinoSlider', cs, (st) => SizedBox(width: 240, child: CupertinoSlider(key: tk, value: 0.5, onChanged: en(st) ? (_) {} : null))),
  Spec('segmented-sliding', 'segmented_control', 'CupertinoSlidingSegmentedControl', ['rest', 'pressed'],
      (st) => CupertinoSlidingSegmentedControl<int>(key: tk, groupValue: 0, onValueChanged: (_) {}, children: const {0: Text('Day'), 1: Text('Week'), 2: Text('Month')}),
      size: const Size(320, 96)),
  Spec('segmented-classic', 'segmented_control', 'CupertinoSegmentedControl', ['rest', 'pressed'],
      (st) => CupertinoSegmentedControl<int>(key: tk, groupValue: 0, onValueChanged: (_) {}, children: const {0: Text('Day'), 1: Text('Week'), 2: Text('Month')}),
      size: const Size(320, 96)),
  Spec('textfield', 'text_edit', 'CupertinoTextField', ['rest', 'focus', 'disabled', 'value'],
      (st) => SizedBox(width: 260, child: CupertinoTextField(key: tk, enabled: en(st), placeholder: 'Placeholder', controller: st == 'value' ? TextEditingController(text: 'Value') : null)),
      size: const Size(300, 96)),
  Spec('search', 'search_field', 'CupertinoSearchTextField', ['rest', 'focus', 'value', 'disabled'],
      (st) => SizedBox(width: 300, child: CupertinoSearchTextField(key: tk, enabled: en(st), controller: st == 'value' ? TextEditingController(text: 'Query') : null)),
      size: const Size(340, 96)),
  Spec('picker', 'list_box', 'CupertinoPicker', ['rest'],
      (st) => SizedBox(height: 200, width: 260, child: CupertinoPicker(itemExtent: 32, onSelectedItemChanged: (_) {}, children: [for (final n in ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot']) Center(child: Text(n))])),
      size: const Size(300, 220)),
  Spec('navigationbar', 'navigation_bar', 'CupertinoNavigationBar', ['rest', 'pressed'],
      (st) => CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(leading: CupertinoNavigationBarBackButton(key: tk, previousPageTitle: 'Back', onPressed: () {}), middle: const Text('Title'), trailing: const Icon(CupertinoIcons.add)),
          child: const SizedBox()),
      size: const Size(390, 120), raw: true, off: Offset.zero),
  Spec('navigationbar-large', 'large_title', 'CupertinoSliverNavigationBar', ['rest'],
      (st) => CupertinoPageScaffold(
          child: CustomScrollView(slivers: [CupertinoSliverNavigationBar(largeTitle: const Text('Settings'), previousPageTitle: 'Back', trailing: const Icon(CupertinoIcons.add)), const SliverFillRemaining()])),
      size: const Size(390, 200), raw: true),
  Spec('tabbar', 'tab_bar', 'CupertinoTabBar', ['rest', 'pressed'],
      (st) => CupertinoPageScaffold(child: Align(alignment: Alignment.bottomCenter, child: CupertinoTabBar(key: tk, currentIndex: 0, onTap: (_) {}, items: const [
            BottomNavigationBarItem(icon: Icon(CupertinoIcons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(CupertinoIcons.search), label: 'Search'),
            BottomNavigationBarItem(icon: Icon(CupertinoIcons.person), label: 'Profile'),
          ]))),
      size: const Size(390, 140), raw: true),
  Spec('actionsheet', 'action_sheet', 'CupertinoActionSheet', ['open'], (st) => const SizedBox(), size: const Size(390, 420), act: (t, st) async {
    showCupertinoModalPopup<void>(
        context: _ctx(t),
        builder: (c) => CupertinoActionSheet(
              title: const Text('Title'),
              message: const Text('Message'),
              actions: [CupertinoActionSheetAction(onPressed: () {}, child: const Text('Action')), CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () {}, child: const Text('Delete'))],
              cancelButton: CupertinoActionSheetAction(onPressed: () {}, child: const Text('Cancel')),
            ));
    await _settle(t);
  }),
  Spec('alertdialog', 'alert_dialog', 'CupertinoAlertDialog', ['open'], (st) => const SizedBox(), size: const Size(390, 320), act: (t, st) async {
    showCupertinoDialog<void>(
        context: _ctx(t),
        builder: (c) => CupertinoAlertDialog(
              title: const Text('Delete item?'),
              content: const Text('This item will be removed permanently.'),
              actions: [CupertinoDialogAction(onPressed: () {}, child: const Text('Cancel')), CupertinoDialogAction(isDestructiveAction: true, onPressed: () {}, child: const Text('Delete'))],
            ));
    await _settle(t);
  }),
  Spec('checkbox', 'checkbox', 'CupertinoCheckbox', [...css, 'indeterminate'],
      (st) => CupertinoCheckbox(key: tk, tristate: true, value: st == 'selected' ? true : (st == 'indeterminate' ? null : false), onChanged: en(st) ? (_) {} : null)),
  Spec('radio', 'radio', 'CupertinoRadio', css,
      (st) => RadioGroup<int>(groupValue: st == 'selected' ? 1 : null, onChanged: (_) {}, child: CupertinoRadio<int>(key: tk, value: 1, enabled: en(st)))),
  Spec('listsection', 'list', 'CupertinoListSection/CupertinoListTile', ['rest', 'pressed'], _section, size: const Size(390, 280), raw: true),
  Spec('contextmenu', 'popup_menu', 'CupertinoContextMenu', ['open'],
      (st) => CupertinoContextMenu(key: tk, actions: [
            CupertinoContextMenuAction(onPressed: () {}, trailingIcon: CupertinoIcons.share, child: const Text('Share')),
            CupertinoContextMenuAction(onPressed: () {}, trailingIcon: CupertinoIcons.heart, child: const Text('Favorite')),
            CupertinoContextMenuAction(isDestructiveAction: true, onPressed: () {}, trailingIcon: CupertinoIcons.delete, child: const Text('Delete')),
          ], child: Container(width: 120, height: 120, decoration: BoxDecoration(color: CupertinoColors.systemBlue, borderRadius: BorderRadius.circular(16)))),
      size: const Size(390, 520), act: (t, st) async {
    final g = await t.startGesture(t.getCenter(find.byKey(tk)));
    await t.pump(const Duration(milliseconds: 1500));
    await t.pump(const Duration(milliseconds: 1000));
    await g.up();
    await t.pump(const Duration(milliseconds: 1000));
  }),
  for (final m in ['date', 'time', 'dateAndTime'])
    Spec('datepicker-$m', m == 'time' ? 'time_picker' : 'date_picker', 'CupertinoDatePicker', ['rest'],
        (st) => SizedBox(
            height: 216,
            width: 340,
            child: CupertinoDatePicker(
                mode: {'date': CupertinoDatePickerMode.date, 'time': CupertinoDatePickerMode.time, 'dateAndTime': CupertinoDatePickerMode.dateAndTime}[m]!,
                initialDateTime: DateTime(2026, 10, 20, 10, 30),
                onDateTimeChanged: (_) {})),
        size: const Size(380, 240)),
];

