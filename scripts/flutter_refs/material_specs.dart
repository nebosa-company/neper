import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'harness.dart';

bool en(String st) => st != 'disabled';
VoidCallback? cb(String st) => en(st) ? () {} : null;
final ttKey = GlobalKey<TooltipState>();
final popKey = GlobalKey<PopupMenuButtonState<int>>();
final menuCtl = MenuController();
void _n() {}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 700));
}

BuildContext _ctx(WidgetTester t) => t.element(find.byType(Scaffold).first);

Widget _tabs(bool secondary) => DefaultTabController(
      length: 3,
      child: SizedBox(
        width: 360,
        child: secondary
            ? TabBar.secondary(key: tk, tabs: const [Tab(text: 'Videos'), Tab(text: 'Photos'), Tab(text: 'Audio')])
            : TabBar(key: tk, tabs: const [Tab(icon: Icon(Icons.flight), text: 'Flights'), Tab(icon: Icon(Icons.hotel), text: 'Hotels'), Tab(icon: Icon(Icons.map), text: 'Maps')]),
      ),
    );

final materialSpecs = <Spec>[
  for (final v in ['elevated', 'filled', 'tonal', 'outlined', 'text'])
    Spec('button-$v', 'button', {'elevated': 'ElevatedButton', 'filled': 'FilledButton', 'tonal': 'FilledButton.tonal', 'outlined': 'OutlinedButton', 'text': 'TextButton'}[v]!, std, (st) {
      const l = Text('Button');
      return switch (v) {
        'elevated' => ElevatedButton(key: tk, onPressed: cb(st), child: l),
        'filled' => FilledButton(key: tk, onPressed: cb(st), child: l),
        'tonal' => FilledButton.tonal(key: tk, onPressed: cb(st), child: l),
        'outlined' => OutlinedButton(key: tk, onPressed: cb(st), child: l),
        _ => TextButton(key: tk, onPressed: cb(st), child: l),
      };
    }),
  for (final v in ['standard', 'filled', 'tonal', 'outlined'])
    Spec('iconbutton-$v', 'icon_button', 'IconButton', sel, (st) {
      const i = Icon(Icons.favorite_border);
      const si = Icon(Icons.favorite);
      final s = st == 'selected';
      return switch (v) {
        'standard' => IconButton(key: tk, isSelected: s, selectedIcon: si, icon: i, onPressed: cb(st)),
        'filled' => IconButton.filled(key: tk, isSelected: s, selectedIcon: si, icon: i, onPressed: cb(st)),
        'tonal' => IconButton.filledTonal(key: tk, isSelected: s, selectedIcon: si, icon: i, onPressed: cb(st)),
        _ => IconButton.outlined(key: tk, isSelected: s, selectedIcon: si, icon: i, onPressed: cb(st)),
      };
    }),
  Spec('checkbox', 'checkbox', 'Checkbox', [...sel, 'indeterminate'],
      (st) => Checkbox(key: tk, tristate: true, value: st == 'selected' ? true : (st == 'indeterminate' ? null : false), onChanged: en(st) ? (_) {} : null)),
  Spec('radio', 'radio', 'Radio', sel,
      (st) => RadioGroup<int>(groupValue: st == 'selected' ? 1 : null, onChanged: (_) {}, child: Radio<int>(key: tk, value: 1, enabled: en(st)))),
  Spec('switch', 'switch', 'Switch', sel, (st) => Switch(key: tk, value: st == 'selected', onChanged: en(st) ? (_) {} : null)),
  Spec('slider', 'slider', 'Slider', std, (st) => SizedBox(width: 240, child: Slider(key: tk, value: 0.5, onChanged: en(st) ? (_) {} : null))),
  Spec('slider-discrete', 'slider', 'Slider(divisions, label)', std,
      (st) => SizedBox(width: 240, child: Slider(key: tk, value: 0.5, divisions: 10, label: '50', onChanged: en(st) ? (_) {} : null))),
  Spec('rangeslider', 'range_slider', 'RangeSlider', std,
      (st) => SizedBox(width: 240, child: RangeSlider(key: tk, values: const RangeValues(0.5, 0.9), onChanged: en(st) ? (_) {} : null))),
  for (final filled in [true, false])
    Spec(filled ? 'textfield-filled' : 'textfield-outlined', 'text_edit', 'TextField', ['rest', 'hover', 'focus', 'disabled', 'error', 'value'], (st) {
      return SizedBox(
        width: 260,
        child: TextField(
          key: tk,
          enabled: en(st),
          controller: st == 'value' ? TextEditingController(text: 'Value') : null,
          decoration: InputDecoration(
            filled: filled,
            border: filled ? null : const OutlineInputBorder(),
            labelText: 'Label',
            helperText: 'Supporting text',
            errorText: st == 'error' ? 'Error text' : null,
          ),
        ),
      );
    }, size: const Size(300, 120)),
  Spec('chip-assist', 'chip', 'ActionChip', std, (st) => ActionChip(key: tk, avatar: const Icon(Icons.event, size: 18), label: const Text('Assist'), onPressed: cb(st))),
  Spec('chip-filter', 'chip', 'FilterChip', sel, (st) => FilterChip(key: tk, label: const Text('Filter'), selected: st == 'selected', onSelected: en(st) ? (_) {} : null)),
  Spec('chip-choice', 'chip', 'ChoiceChip', sel, (st) => ChoiceChip(key: tk, label: const Text('Choice'), selected: st == 'selected', onSelected: en(st) ? (_) {} : null)),
  Spec('chip-input', 'chip', 'InputChip', sel,
      (st) => InputChip(key: tk, avatar: const CircleAvatar(child: Text('A')), label: const Text('Input'), selected: st == 'selected', onPressed: cb(st), onDeleted: en(st) ? () {} : null)),
  Spec('chip-static', 'chip', 'Chip', ['rest'], (st) => const Chip(label: Text('Chip'))),
  Spec('segmentedbutton', 'segmented_control', 'SegmentedButton', std,
      (st) => SegmentedButton<int>(key: tk, showSelectedIcon: true, segments: const [
            ButtonSegment(value: 0, label: Text('Day')),
            ButtonSegment(value: 1, label: Text('Week')),
            ButtonSegment(value: 2, label: Text('Month')),
          ], selected: const {0}, onSelectionChanged: en(st) ? (_) {} : null),
      size: const Size(320, 96)),
  Spec('progress-linear', 'progress_bar', 'LinearProgressIndicator', ['rest', 'indeterminate'],
      (st) => SizedBox(width: 240, child: LinearProgressIndicator(key: tk, value: st == 'rest' ? 0.6 : null))),
  Spec('progress-circular', 'activity_indicator', 'CircularProgressIndicator', ['rest', 'indeterminate'],
      (st) => CircularProgressIndicator(key: tk, value: st == 'rest' ? 0.6 : null)),
  for (final v in ['elevated', 'filled', 'outlined'])
    Spec('card-$v', 'card', 'Card', std, (st) {
      final c = InkWell(onTap: cb(st), child: const Padding(padding: EdgeInsets.all(16), child: Text('Card title\nSupporting text')));
      final w = SizedBox(width: 200, child: switch (v) {
        'elevated' => Card(key: tk, clipBehavior: Clip.antiAlias, child: c),
        'filled' => Card.filled(key: tk, clipBehavior: Clip.antiAlias, child: c),
        _ => Card.outlined(key: tk, clipBehavior: Clip.antiAlias, child: c),
      });
      return en(st) ? w : Opacity(opacity: 0.38, child: IgnorePointer(child: w));
    }, size: const Size(280, 120)),
  Spec('listtile', 'list', 'ListTile', sel,
      (st) => SizedBox(
          width: 320,
          child: ListTile(key: tk, enabled: en(st), selected: st == 'selected', onTap: () {}, leading: const Icon(Icons.person), title: const Text('List item'), subtitle: const Text('Supporting text'), trailing: const Icon(Icons.chevron_right))),
      size: const Size(340, 96)),
  Spec('divider', 'divider', 'Divider', ['rest'],
      (st) => const SizedBox(width: 240, height: 90, child: Column(children: [Text('Above'), Divider(), Text('Below'), Divider(indent: 16, endIndent: 16), SizedBox(height: 10, child: VerticalDivider())]))),
  Spec('tooltip', 'hint', 'Tooltip', ['open'], (st) => Tooltip(key: ttKey, message: 'Tooltip text', child: IconButton(key: tk, icon: const Icon(Icons.info_outline), onPressed: () {})),
      size: const Size(240, 120), act: (t, st) async {
    ttKey.currentState!.ensureTooltipVisible();
    await _settle(t);
  }),
  Spec('snackbar', 'snackbar', 'SnackBar', ['open', 'floating'], (st) => const SizedBox(), size: const Size(400, 160), act: (t, st) async {
    ScaffoldMessenger.of(_ctx(t)).showSnackBar(SnackBar(
        behavior: st == 'floating' ? SnackBarBehavior.floating : SnackBarBehavior.fixed,
        content: const Text('Item archived'),
        action: SnackBarAction(label: 'Undo', onPressed: () {})));
    await _settle(t);
  }),
  Spec('banner', 'banner', 'MaterialBanner', ['open'], (st) => const SizedBox(), size: const Size(420, 180), act: (t, st) async {
    ScaffoldMessenger.of(_ctx(t)).showMaterialBanner(MaterialBanner(
        leading: const Icon(Icons.info_outline),
        content: const Text('Your session will expire soon.'),
        actions: [TextButton(onPressed: () {}, child: const Text('Dismiss')), TextButton(onPressed: () {}, child: const Text('Renew'))]));
    await _settle(t);
  }),
  Spec('dialog-alert', 'alert_dialog', 'AlertDialog', ['open'], (st) => const SizedBox(), size: const Size(400, 320), act: (t, st) async {
    showDialog(
        context: _ctx(t),
        builder: (c) => AlertDialog(
            icon: const Icon(Icons.delete_outline),
            title: const Text('Delete item?'),
            content: const Text('This item will be removed permanently.'),
            actions: [TextButton(onPressed: () {}, child: const Text('Cancel')), TextButton(onPressed: () {}, child: const Text('Delete'))]));
    await _settle(t);
  }),
  Spec('dialog-simple', 'dialog', 'SimpleDialog', ['open'], (st) => const SizedBox(), size: const Size(400, 320), act: (t, st) async {
    showDialog(
        context: _ctx(t),
        builder: (c) => SimpleDialog(title: const Text('Select account'), children: [
              SimpleDialogOption(onPressed: () {}, child: const Text('user@example.com')),
              SimpleDialogOption(onPressed: () {}, child: const Text('other@example.com')),
            ]));
    await _settle(t);
  }),
  for (final handle in [true, false])
    Spec(handle ? 'bottomsheet-modal' : 'bottomsheet-nohandle', 'bottom_sheet', 'showModalBottomSheet', ['open'], (st) => const SizedBox(), size: const Size(400, 400), act: (t, st) async {
      showModalBottomSheet(
          context: _ctx(t),
          showDragHandle: handle,
          builder: (c) => const Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(leading: Icon(Icons.share), title: Text('Share')),
                ListTile(leading: Icon(Icons.link), title: Text('Get link')),
                ListTile(leading: Icon(Icons.edit), title: Text('Edit')),
              ]));
      await _settle(t);
    }),
  Spec('tabs-primary', 'tab_bar', 'TabBar', ['rest', 'hover', 'focus', 'pressed'], (st) => _tabs(false), size: const Size(380, 96)),
  Spec('tabs-secondary', 'tab_bar', 'TabBar.secondary', ['rest', 'hover', 'focus', 'pressed'], (st) => _tabs(true), size: const Size(380, 96)),
  Spec('navigationbar', 'navigation_bar', 'NavigationBar', ['rest', 'hover', 'focus', 'pressed'],
      (st) => Scaffold(
          bottomNavigationBar: NavigationBar(key: tk, selectedIndex: 0, onDestinationSelected: (_) {}, destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
        NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
      ])),
      size: const Size(360, 120), raw: true),
  Spec('navigationrail', 'navigation_rail', 'NavigationRail', ['rest', 'hover', 'focus', 'pressed'],
      (st) => Scaffold(
          body: Row(children: [
        NavigationRail(key: tk, selectedIndex: 0, labelType: NavigationRailLabelType.all, onDestinationSelected: (_) {}, leading: FloatingActionButton(elevation: 0, onPressed: () {}, child: const Icon(Icons.add)), destinations: const [
          NavigationRailDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: Text('Home')),
          NavigationRailDestination(icon: Icon(Icons.search), label: Text('Search')),
          NavigationRailDestination(icon: Icon(Icons.person_outline), label: Text('Profile')),
        ]),
      ])),
      size: const Size(120, 360), raw: true),
  Spec('navigationdrawer', 'navigation_drawer', 'NavigationDrawer', ['rest'],
      (st) => Scaffold(
          body: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 300, child: NavigationDrawer(selectedIndex: 0, onDestinationSelected: (_) {}, children: const [
        Padding(padding: EdgeInsets.fromLTRB(28, 16, 16, 10), child: Text('Mail')),
        NavigationDrawerDestination(icon: Icon(Icons.inbox_outlined), selectedIcon: Icon(Icons.inbox), label: Text('Inbox')),
        NavigationDrawerDestination(icon: Icon(Icons.send_outlined), label: Text('Sent')),
        NavigationDrawerDestination(icon: Icon(Icons.delete_outline), label: Text('Trash')),
      ])))),
      size: const Size(320, 320), raw: true),
  Spec('appbar-small', 'top_app_bar', 'AppBar', ['rest'],
      (st) => Scaffold(appBar: AppBar(leading: const Icon(Icons.menu), title: const Text('Title'), actions: const [Icon(Icons.search), SizedBox(width: 16), Icon(Icons.more_vert), SizedBox(width: 8)])),
      size: const Size(360, 120), raw: true),
  Spec('appbar-center', 'top_app_bar', 'AppBar(centerTitle)', ['rest'],
      (st) => Scaffold(appBar: AppBar(centerTitle: true, leading: const Icon(Icons.arrow_back), title: const Text('Title'), actions: const [Icon(Icons.share), SizedBox(width: 16)])),
      size: const Size(360, 120), raw: true),
  Spec('appbar-medium', 'top_app_bar', 'SliverAppBar.medium', ['rest'],
      (st) => Scaffold(body: CustomScrollView(slivers: [SliverAppBar.medium(leading: const Icon(Icons.arrow_back), title: const Text('Title'), actions: const [Icon(Icons.more_vert)])])),
      size: const Size(360, 160), raw: true),
  Spec('appbar-large', 'top_app_bar', 'SliverAppBar.large', ['rest'],
      (st) => Scaffold(body: CustomScrollView(slivers: [SliverAppBar.large(leading: const Icon(Icons.arrow_back), title: const Text('Title'), actions: const [Icon(Icons.more_vert)])])),
      size: const Size(360, 200), raw: true),
  Spec('badge-count', 'badge', 'Badge', ['rest'], (st) => const Row(mainAxisSize: MainAxisSize.min, children: [
        Badge(label: Text('3'), child: Icon(Icons.mail_outline, size: 28)),
        SizedBox(width: 32),
        Badge(label: Text('99+'), child: Icon(Icons.notifications_none, size: 28)),
      ])),
  Spec('badge-dot', 'badge', 'Badge', ['rest'], (st) => const Badge(child: Icon(Icons.mail_outline, size: 28))),
  for (final v in ['small', 'regular', 'large', 'extended'])
    Spec('fab-$v', 'fab', 'FloatingActionButton', ['rest', 'hover', 'focus', 'pressed'], (st) {
      const i = Icon(Icons.add);
      return switch (v) {
        'small' => FloatingActionButton.small(key: tk, onPressed: () {}, child: i),
        'regular' => FloatingActionButton(key: tk, onPressed: () {}, child: i),
        'large' => FloatingActionButton.large(key: tk, onPressed: () {}, child: i),
        _ => FloatingActionButton.extended(key: tk, onPressed: () {}, icon: i, label: const Text('Compose')),
      };
    }, size: const Size(240, 120)),
  Spec('menu-popup', 'popup_menu', 'PopupMenuButton', ['open'],
      (st) => Scaffold(body: Align(alignment: Alignment.topLeft, child: Padding(padding: const EdgeInsets.all(16), child: PopupMenuButton<int>(key: popKey, itemBuilder: (c) => const [
            PopupMenuItem(value: 1, child: Text('Cut')),
            PopupMenuItem(value: 2, child: Text('Copy')),
            PopupMenuItem(value: 3, child: Text('Paste')),
          ])))),
      size: const Size(260, 240), raw: true, act: (t, st) async {
    popKey.currentState!.showButtonMenu();
    await _settle(t);
  }),
  Spec('menu-anchor', 'popup_menu', 'MenuAnchor', ['open'],
      (st) => Scaffold(body: Align(alignment: Alignment.topLeft, child: Padding(padding: const EdgeInsets.all(16), child: MenuAnchor(controller: menuCtl, menuChildren: const [
            MenuItemButton(leadingIcon: Icon(Icons.content_cut), shortcut: SingleActivator(LogicalKeyboardKey.keyX, control: true), onPressed: _n, child: Text('Cut')),
            MenuItemButton(leadingIcon: Icon(Icons.copy), shortcut: SingleActivator(LogicalKeyboardKey.keyC, control: true), onPressed: _n, child: Text('Copy')),
            MenuItemButton(leadingIcon: Icon(Icons.paste), onPressed: null, child: Text('Paste')),
          ], child: IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}))))),
      size: const Size(300, 240), raw: true, act: (t, st) async {
    menuCtl.open();
    await _settle(t);
  }),
  Spec('dropdownmenu', 'combo_box', 'DropdownMenu', ['rest', 'hover', 'focus', 'disabled', 'open'],
      (st) => Scaffold(body: Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.only(top: 24), child: DropdownMenu<int>(key: tk, enabled: en(st), label: const Text('Colour'), initialSelection: 1, dropdownMenuEntries: const [
            DropdownMenuEntry(value: 1, label: 'Red'),
            DropdownMenuEntry(value: 2, label: 'Green'),
            DropdownMenuEntry(value: 3, label: 'Blue'),
          ])))),
      size: const Size(320, 260), raw: true, act: (t, st) async {
    await t.tap(find.byKey(tk));
    await _settle(t);
  }),
  Spec('datepicker-calendar', 'date_picker', 'showDatePicker', ['open'], (st) => const SizedBox(), size: const Size(400, 640), act: (t, st) async {
    showDatePicker(context: _ctx(t), initialDate: DateTime(2026, 10, 20), firstDate: DateTime(2020), lastDate: DateTime(2030));
    await _settle(t);
  }),
  Spec('datepicker-input', 'date_picker', 'showDatePicker(input)', ['open'], (st) => const SizedBox(), size: const Size(400, 400), act: (t, st) async {
    showDatePicker(context: _ctx(t), initialEntryMode: DatePickerEntryMode.input, initialDate: DateTime(2026, 10, 20), firstDate: DateTime(2020), lastDate: DateTime(2030));
    await _settle(t);
  }),
  Spec('daterangepicker', 'date_range_picker', 'showDateRangePicker', ['open'], (st) => const SizedBox(), size: const Size(400, 720), act: (t, st) async {
    showDateRangePicker(context: _ctx(t), initialDateRange: DateTimeRange(start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 20)), firstDate: DateTime(2020), lastDate: DateTime(2030));
    await _settle(t);
  }),
  Spec('timepicker-dial', 'time_picker', 'showTimePicker', ['open'], (st) => const SizedBox(), size: const Size(400, 560), act: (t, st) async {
    showTimePicker(context: _ctx(t), initialTime: const TimeOfDay(hour: 10, minute: 30));
    await _settle(t);
  }),
  Spec('timepicker-input', 'time_picker', 'showTimePicker(input)', ['open'], (st) => const SizedBox(), size: const Size(400, 400), act: (t, st) async {
    showTimePicker(context: _ctx(t), initialEntryMode: TimePickerEntryMode.input, initialTime: const TimeOfDay(hour: 10, minute: 30));
    await _settle(t);
  }),
  Spec('stepper-vertical', 'wizard', 'Stepper', ['rest'],
      (st) => SizedBox(width: 380, height: 380, child: Stepper(currentStep: 1, onStepContinue: () {}, onStepCancel: () {}, steps: const [
            Step(title: Text('Account'), content: Text('Create account'), state: StepState.complete),
            Step(title: Text('Profile'), content: Text('Fill profile'), isActive: true),
            Step(title: Text('Finish'), content: Text('Done')),
          ])),
      size: const Size(400, 400)),
  Spec('stepper-horizontal', 'wizard', 'Stepper(horizontal)', ['rest'],
      (st) => SizedBox(width: 420, height: 260, child: Stepper(type: StepperType.horizontal, currentStep: 1, onStepContinue: () {}, onStepCancel: () {}, steps: const [
            Step(title: Text('Account'), content: Text('Create account'), state: StepState.complete),
            Step(title: Text('Profile'), content: Text('Fill profile'), isActive: true),
            Step(title: Text('Finish'), content: Text('Done')),
          ])),
      size: const Size(440, 280)),
  Spec('expansiontile', 'accordion', 'ExpansionTile', ['rest', 'hover', 'focus', 'pressed', 'expanded'],
      (st) => SizedBox(width: 320, child: ExpansionTile(key: tk, initiallyExpanded: st == 'expanded', leading: const Icon(Icons.folder_outlined), title: const Text('Section'), subtitle: const Text('Supporting text'), children: const [ListTile(title: Text('Child one')), ListTile(title: Text('Child two'))])),
      size: const Size(340, 240), act: (t, st) async => t.pump(const Duration(milliseconds: 400))),
  Spec('datatable', 'table', 'DataTable', ['rest', 'selected'],
      (st) => DataTable(showCheckboxColumn: true, sortColumnIndex: 1, columns: const [
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Qty'), numeric: true),
            DataColumn(label: Text('Price'), numeric: true),
          ], rows: [
            DataRow(selected: st == 'selected', onSelectChanged: (_) {}, cells: const [DataCell(Text('Apple')), DataCell(Text('4')), DataCell(Text('1.20'))]),
            DataRow(onSelectChanged: (_) {}, cells: const [DataCell(Text('Pear')), DataCell(Text('12')), DataCell(Text('0.80'))]),
            DataRow(onSelectChanged: (_) {}, cells: const [DataCell(Text('Plum')), DataCell(Text('7')), DataCell(Text('2.10'))]),
          ]),
      size: const Size(420, 220)),
  Spec('searchbar', 'search_bar', 'SearchBar', ['rest', 'hover', 'focus', 'value', 'disabled'],
      (st) => SizedBox(width: 380, child: SearchBar(key: tk, enabled: en(st), hintText: 'Search', controller: st == 'value' ? TextEditingController(text: 'Query') : null, leading: const Icon(Icons.search), trailing: const [Icon(Icons.mic)])),
      size: const Size(420, 96)),
];
