'use strict';
'require view';
'require uci';

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		return uci.load('mihomo');
	},

	render: function() {
		var port = uci.get('mihomo', 'main', 'controller_port') || '9090';
		var uiPath = uci.get('mihomo', 'main', 'ui_path') || 'ui';
		var iframeSrc = '//' + window.location.hostname + ':' + port + '/' + uiPath + '/';

		return E('div', { 'class': 'cbi-map' }, [
			E('iframe', {
				src: iframeSrc,
				style: 'width: 100%; height: calc(100vh - 120px); border: none; border-radius: 4px;',
				allowtransparency: 'true'
			})
		]);
	}
});
